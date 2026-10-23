// The trip screen's application layer (contracts/trip-controller.md): it
// owns the engine, the session, the phase, the economy calls and the record
// writes. Widgets and the Flame scene talk only to it.
import 'dart:async';

import 'package:content_models/content_models.dart';
import 'package:flutter/foundation.dart';
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/core/config/config_source.dart';
import 'package:wassal/core/config/tunable.dart';
import 'package:wassal/core/config/tunable_snapshot.dart';
import 'package:wassal/core/content/domain/content_source.dart';
import 'package:wassal/core/economy/economy.dart';
import 'package:wassal/features/trip/application/trip_ad_offers.dart';
import 'package:wassal/features/trip/application/trip_phase.dart';
import 'package:wassal/features/trip/application/trip_session.dart';
import 'package:wassal/features/trip/data/trip_kill_point.dart';
import 'package:wassal/features/trip/data/trip_records.dart';
import 'package:wassal/features/trip/domain/cues.dart';
import 'package:wassal/features/trip/domain/fail_summary.dart';
import 'package:wassal/features/trip/domain/hints.dart';
import 'package:wassal/features/trip/domain/line_ids.dart';
import 'package:wassal/features/trip/domain/presentation_memory.dart';
import 'package:wassal/features/trip/domain/projection.dart';
import 'package:wassal/features/trip/domain/speech.dart';
import 'package:wassal/features/trip/domain/step_accumulator.dart';
import 'package:wassal/features/trip/domain/trip_facts.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';
import 'package:wassal/features/trip/domain/wire.dart';

/// A rejection line stays this long in the log's place.
const rejectionLineMs = 2000;

/// A trip that a test opens from a fixture instead of the active pack.
final class FixedTrip {
  const FixedTrip({
    required this.definition,
    required this.params,
    required this.seed,
  });

  final TripDefinition definition;
  final TripParams params;
  final int seed;
}

final class TripController {
  TripController({
    required this._economy,
    required this._content,
    required this._contentVersion,
    required this._config,
    required this._records,
    required this._piasters,
    required this._stationLetter,
    Set<String> Function()? hintsSeen,
    this._onHintSeen,
    this._ads = const NoTripAdOffers(),
    int Function()? nowMs,
    this.onKillPoint,
    FixedTrip? fixedTrip,
  }) : _hintsSeen = hintsSeen ?? (() => const {}),
       _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch),
       _fixed = fixedTrip;

  /// Opens [trip] from a fixture's definition, params and seed: the
  /// scripted player's entry (contracts/trip-controller.md "Test seams").
  factory TripController.forDefinition(
    FixedTrip trip, {
    required Economy economy,
    required ContentSource Function() content,
    required TripRecords records,
    required ConfigSource Function() config,
    String Function(int piasters)? piasters,
    String Function(int slot)? stationLetter,
    TripAdOffers ads = const NoTripAdOffers(),
  }) => TripController(
    economy: economy,
    content: content,
    contentVersion: () => 1,
    config: config,
    records: records,
    piasters: piasters ?? (p) => '$p',
    stationLetter: stationLetter ?? (slot) => '$slot',
    ads: ads,
    fixedTrip: trip,
  );

  final Economy _economy;
  final ContentSource Function() _content;
  final int Function() _contentVersion;
  final ConfigSource Function() _config;
  final TripRecords _records;
  final String Function(int piasters) _piasters;
  final String Function(int slot) _stationLetter;
  final Set<String> Function() _hintsSeen;
  final void Function(String archetypeWire)? _onHintSeen;
  final TripAdOffers _ads;
  final int Function() _nowMs;
  final FixedTrip? _fixed;
  final void Function(TripKillPoint point)? onKillPoint;

  final _models = StreamController<TripModel>.broadcast(sync: true);
  final _cues = StreamController<TripCue>.broadcast(sync: true);
  final _frames = ValueNotifier<int>(0);
  final _accumulator = StepAccumulator();

  String? _tripId;
  TripSession? _session;
  _PendingStart? _pendingStart;
  PresentationMemory _memory = PresentationMemory.empty;
  HintState _hints = HintState.empty;
  TripPhase _phase = TripPhase.opening;
  TripRetry? _retry;
  TripExit? _exit;
  PauseReason? _pauseReason;
  int? _nextLiterAtMs;
  bool _breakMode = false;
  bool _controlsLocked = false;
  RejectionLine? _rejection;
  final Set<BoosterId> _disabledBoosters = {};

  /// Booster uses not charged yet, by request id: in flight, or whose
  /// charge failed to write. Each counts against the stock until it is
  /// charged; a failed one is sent again with the next use, before the
  /// result is recorded, and by the next rebuild (from its intent).
  final Map<TxnId, _Use> _uncharged = {};
  final List<int> _disputes = [];
  BoosterId? _boosterCard;
  int? _boosterShortBy;
  TxnId? _resultId;
  TxnId? _purchaseId;
  TxnId? _reviveId;
  _PendingResult? _pendingResult;
  bool _reviveHidden = false;
  bool _disposed = false;
  late TripModel _model = const TripModel(phase: TripPhase.opening);

  TripPhase get phase => _phase;
  TripModel get model => _model;
  TripView? get view => _model.view;
  Stream<TripModel> get models => _models.stream;

  /// One-shot effects, in order.
  Stream<TripCue> get cues => _cues.stream;

  /// How far into the next step the clock is, for smooth movement.
  double get alpha => _accumulator.alpha;

  /// Ticks after every [advance], for what redraws each frame.
  ValueListenable<int> get frames => _frames;

  /// The engine, for tests.
  @visibleForTesting
  TripEngine? get engine => _session?.engine;

  /// Shows [model] as if the engine had produced it: the design samples'
  /// states on the real screen (goldens and layout tests).
  @visibleForTesting
  void debugShowModel(TripModel model) {
    _model = model;
    _models.add(model);
    _frames.value++;
  }

  /// What internal builds' debug panel shows, read-only: the engine's state
  /// and its replay record (research R21).
  ({TripState state, ReplayRecord record})? get debugSnapshot =>
      switch (_session?.engine) {
        final engine? => (state: engine.state, record: engine.replayRecord),
        null => null,
      };

  TripSession? get session => _session;

  // ---------------------------------------------------------------- Opening

  /// Starts [tripId], resumes it, or redirects to the unfinished one.
  Future<void> open(String tripId) async {
    _tripId = tripId;
    _setPhase(TripPhase.opening);
    for (var attempt = 0; attempt < 2; attempt++) {
      final unfinished = _economy.view.unfinished;
      if (unfinished != null && unfinished.tripId != tripId) {
        return _end(ExitToTrip(unfinished.tripId));
      }
      if (unfinished != null) return _resume(unfinished);
      if (await _start(tripId)) return;
    }
    _end(const ExitToHome());
  }

  /// False when the start should be tried again from the top (a race with
  /// another open).
  Future<bool> _start(String tripId) async {
    final fixed = _fixed;
    final definition = fixed?.definition ?? _content().trip(tripId);
    if (definition == null) {
      _end(const ExitToHome());
      return true;
    }
    final facts = _factsFor(definition, params: fixed?.params);
    final id = _economy.newRequestId();
    _pendingStart = _PendingStart(
      header: TripRecordHeader(
        startTxn: id,
        tripId: definition.tripId,
        contentVersion: _contentVersion(),
        definition: definition,
        seed: fixed?.seed ?? definition.seed,
        params: facts.params,
        createdAtMs: _nowMs(),
      ),
      facts: facts,
    );
    return _sendStart();
  }

  Future<bool> _sendStart() async {
    final pending = _pendingStart!;
    final header = pending.header;
    if (!pending.written) {
      pending.written = await _records.create(header);
      if (!pending.written) {
        _retry = TripRetry.start;
        _publish();
        return true;
      }
    }
    final outcome = await _economy.startTrip(
      header.startTxn,
      tripId: header.tripId,
    );
    switch (outcome) {
      case OpApplied():
        _kill(TripKillPoint.startApplied);
        _pendingStart = null;
        _retry = null;
        _session = TripSession(
          startTxn: header.startTxn,
          contentVersion: header.contentVersion,
          seed: header.seed,
          facts: pending.facts,
          engine: TripEngine.start(
            header.definition,
            header.params,
            seed: header.seed,
          ),
        );
        _memory = PresentationMemory.empty;
        _hints = HintState.empty;
        _openHints();
        _setPhase(TripPhase.running);
        return true;
      case OpRefused(code: EconomyRefusal.noFuel):
        await _records.delete(header.startTxn);
        _pendingStart = null;
        _nextLiterAtMs = _economy.view.fuel.nextLiterAtMs;
        _setPhase(TripPhase.noFuel);
        return true;
      case OpRefused(code: EconomyRefusal.tripUnfinished):
        await _records.delete(header.startTxn);
        _pendingStart = null;
        return false;
      case OpRefused():
        await _records.delete(header.startTxn);
        _pendingStart = null;
        _end(const ExitToHome());
        return true;
      case OpWriteFailed():
        _retry = TripRetry.start;
        _publish();
        return true;
    }
  }

  TripFacts _factsFor(TripDefinition definition, {TripParams? params}) {
    final config = _config();
    final line = toGlossaryLine(definition.lineId);
    return TripFacts(
      definition: definition,
      line: _content().line(definition.lineId),
      params:
          params ??
          TripParams.fromTunables(tunableSnapshot(config), definition.lineId),
      bubbleMinMs: config.read(Tunable.tripBubbleMinMs(line)),
      hintMode: switch (config.read(Tunable.tripHintsMode(line))) {
        TripHintsMode.off => HintMode.off,
        TripHintsMode.firstTime => HintMode.firstTime,
        TripHintsMode.always => HintMode.always,
      },
    );
  }

  /// Rebuilds the unfinished trip from its record (contracts/trip-records.md
  /// "Rebuild").
  Future<void> _resume(UnfinishedTrip unfinished) async {
    final stored = await _records.load(unfinished.startTxn);
    TripEngine? engine;
    if (stored != null) {
      try {
        engine = TripEngine.rebuild(stored.toReplayRecord());
      } on RebuildRefused {
        engine = null;
      } on TripRefused {
        engine = null;
      }
    }
    if (stored == null || engine == null) {
      return _endWithoutRecord(unfinished);
    }
    _session = TripSession(
      startTxn: unfinished.startTxn,
      contentVersion: stored.contentVersion,
      seed: stored.seed,
      facts: _factsFor(engine.definition, params: engine.params),
      engine: engine,
    );
    _memory = PresentationMemory.empty;
    _hints = HintState.empty;
    _openHints();
    _uncharged
      ..clear()
      ..addAll({
        for (final intent in stored.intents)
          intent.requestTxn: _Use(intent, Future.value()),
      });
    await _charge();
    final state = engine.state;
    if (state.status == TripStatus.failed &&
        unfinished.revived &&
        !state.revived) {
      // Paid before the kill; the trip comes back paused like any other.
      _applyRevive();
    }
    _disputes
      ..clear()
      ..addAll(engine.state.disputes.keys.toList()..sort());
    switch (engine.status) {
      case TripStatus.paused:
        _pauseReason = PauseReason.lifecycle;
        _setPhase(TripPhase.paused);
      case TripStatus.running:
        engine.pause();
        _pauseReason = PauseReason.lifecycle;
        _setPhase(TripPhase.paused);
      case TripStatus.failed:
        _setPhase(TripPhase.failed);
      case TripStatus.finished || TripStatus.abandoned:
        await _recordResult(engine.result!, exit: _exitFor(engine.result!));
    }
  }

  /// The economy has an unfinished start whose record is missing or
  /// refused: record it abandoned (contracts/trip-controller.md).
  Future<void> _endWithoutRecord(UnfinishedTrip unfinished) async {
    final result = abandonedResult(
      unfinished.tripId,
      _content().trip(unfinished.tripId),
      (definition) => _factsFor(definition).params,
    );
    final id = _resultId ??= _economy.newRequestId();
    final outcome = await _economy.recordResult(
      id,
      start: unfinished.startTxn,
      result: result,
    );
    if (outcome is OpWriteFailed) {
      _pendingResult = _PendingResult(
        result,
        const ExitToHome(),
        start: unfinished.startTxn,
      );
      _retry = TripRetry.result;
      _setPhase(TripPhase.ending);
      return;
    }
    _resultId = null;
    await _records.delete(unfinished.startTxn);
    _end(const ExitToHome());
  }

  // ---------------------------------------------------------------- Time

  /// The frame clock: steps the engine in 33 ms steps while running, and
  /// [settledSpeedUp] times as many once nothing is left for the player.
  void advance(Duration frameTime) {
    final session = _session;
    if (_phase != TripPhase.running || session == null || _disposed) return;
    final steps = _accumulator.add(frameTime * _speed);
    for (var i = 0; i < steps && _phase == TripPhase.running; i++) {
      final before = session.engine.state;
      final events = session.engine.step();
      _absorb(events, before);
      _afterEvents(events);
    }
    if (steps == 0) {
      _frames.value++;
      return;
    }
    _publish();
    _frames.value++;
  }

  // ---------------------------------------------------------------- Intents

  void pick(int denomination) => _command(PickFromTray(denomination));

  void returnHand() => _command(const ReturnHand());

  void send(String passengerId) => _command(SendHand(passengerId));

  void undo() => _command(const UndoLastSend());

  void tap(String passengerId) => _command(Tap(passengerId));

  void answerClaim(String passengerId, {required bool insist}) =>
      _command(ResolveClaim(passengerId, insist: insist));

  void answerChangeRequest(String passengerId, {required bool agree}) =>
      _command(ResolveChangeRequest(passengerId, agree: agree));

  /// Answers the dispute being asked.
  void answerDispute(String paidPassengerId) {
    if (_phase != TripPhase.disputeOpen || _disputes.isEmpty) return;
    final id = _disputes.first;
    final outcome = _command(
      ResolveDispute(id, paidPassengerId),
      phases: const {TripPhase.disputeOpen},
    );
    if (outcome is! Accepted) return;
    _disputes.remove(id);
    if (_phase != TripPhase.disputeOpen) return;
    if (_disputes.isNotEmpty) return _publish();
    _session!.engine.resume();
    _setPhase(TripPhase.running);
  }

  void startBreak() {
    final state = _session?.engine.state;
    if (_phase != TripPhase.running || state == null || _controlsLocked) {
      return;
    }
    if (state.breaksLeft <= 0) return _reject(RejectionCode.breakLimit);
    _breakMode = true;
    _publish();
  }

  void pickBreak(int denomination) {
    if (!_breakMode) return;
    _breakMode = false;
    _command(RequestBreak(denomination));
    _publish();
  }

  void cancelBreak() {
    if (!_breakMode) return;
    _breakMode = false;
    _publish();
  }

  void collect(int tokenId) => _command(CollectDropped(tokenId));

  /// Uses [booster], or opens its purchase card when none is left.
  Future<void> useBooster(BoosterId booster) async {
    final session = _session;
    if (_phase != TripPhase.running || session == null || _controlsLocked) {
      return;
    }
    if ((_stock()[booster] ?? 0) == 0) {
      if (_disabledBoosters.contains(booster) ||
          _price(SkuKind.booster, booster) == null) {
        return;
      }
      session.engine.pause();
      _saveClock();
      _accumulator.clear();
      _boosterCard = booster;
      _boosterShortBy = null;
      _setPhase(TripPhase.boosterCard);
      return;
    }
    await _useOwned(booster);
  }

  Future<void> _useOwned(BoosterId booster) async {
    final session = _session!;
    final engine = session.engine;
    final state = engine.state;
    if ((state.status != TripStatus.running &&
            state.status != TripStatus.paused) ||
        (_stock()[booster] ?? 0) == 0) {
      return;
    }
    if (booster == BoosterId.trafficJam &&
        state.boostersUsed.where((b) => b == booster).length >=
            session.params.boosterTrafficJamMaxPerTrip) {
      return _reject(RejectionCode.boosterLimit);
    }
    final id = _economy.newRequestId();
    final outcome = engine.apply(UseBooster(booster));
    if (outcome is Rejected) return _reject(outcome.rejection.code);
    final accepted = outcome as Accepted;
    final intent = TripIntent(
      requestTxn: id,
      startTxn: session.startTxn,
      booster: booster,
    );
    // Queued before any later command, in the same microtask.
    final written = _records.appendBoosterUse(
      session.startTxn,
      engine.commandLog.last,
      intent,
    );
    _uncharged[id] = _Use(intent, written);
    _absorb(accepted.events, state);
    _afterEvents(accepted.events);
    _publish();
    await _charge();
    _publish();
  }

  /// The boosters the player can use: the economy's stock, less the uses
  /// not charged yet.
  Map<BoosterId, int> _stock() {
    final stock = {..._economy.view.inventory};
    for (final use in _uncharged.values) {
      final booster = use.intent.booster;
      final count = stock[booster] ?? 0;
      if (count > 0) stock[booster] = count - 1;
    }
    return stock;
  }

  /// Charges every use not charged yet, one at a time, each once; true
  /// when none is left.
  Future<bool> _charge() async {
    for (final use in [..._uncharged.values]) {
      await (use.charging ??= _send(use));
    }
    return _uncharged.isEmpty;
  }

  /// Charges [use] once its record is written. Applied or refused, it is
  /// done (a refusal is reported to M15 later; the engine's use stands); a
  /// failed write keeps it for the next try.
  Future<void> _send(_Use use) async {
    await use.written;
    final intent = use.intent;
    final spent = await _economy.useBooster(
      intent.requestTxn,
      booster: intent.booster,
    );
    if (spent is OpWriteFailed) {
      use.charging = null;
      return;
    }
    _uncharged.remove(intent.requestTxn);
    await _records.deleteIntent(intent.requestTxn);
  }

  /// Buys the booster on the card, then uses it.
  Future<void> buyBooster() async {
    final booster = _boosterCard;
    if (_phase != TripPhase.boosterCard || booster == null) return;
    final id = _purchaseId ??= _economy.newRequestId();
    final outcome = await _economy.buy(
      id,
      kind: SkuKind.booster,
      skuId: wireOf(booster),
    );
    // A second tap's answer to the same purchase: the first has it.
    if (_phase != TripPhase.boosterCard || _boosterCard != booster) return;
    switch (outcome) {
      case OpApplied():
        _purchaseId = null;
        _retry = null;
        _closeCard();
        await _useOwned(booster);
      case OpRefused(code: EconomyRefusal.insufficientFunds):
        _purchaseId = null;
        _retry = null;
        final price = _price(SkuKind.booster, booster) ?? 0;
        _boosterShortBy = price - _economy.view.bonat;
        _publish();
      case OpRefused(code: EconomyRefusal.notForSale):
        _purchaseId = null;
        _retry = null;
        _disabledBoosters.add(booster);
        _closeCard();
      case OpRefused():
        _purchaseId = null;
        _retry = null;
        _closeCard();
      case OpWriteFailed():
        _retry = TripRetry.purchase;
        _publish();
    }
  }

  void closeBoosterCard() {
    if (_phase != TripPhase.boosterCard) return;
    _purchaseId = null;
    _retry = null;
    _closeCard();
  }

  void _closeCard() {
    _boosterCard = null;
    _boosterShortBy = null;
    _session?.engine.resume();
    _setPhase(TripPhase.running);
  }

  /// Pays for a revive, then applies it.
  Future<void> revive() async {
    final offer = _reviveOffer();
    if (_phase != TripPhase.failed || offer == null || !offer.affordable) {
      return;
    }
    final id = _reviveId ??= _economy.newRequestId();
    final outcome = await _economy.buy(
      id,
      kind: SkuKind.revive,
      skuId: wireOf(BoosterId.revive),
    );
    switch (outcome) {
      case OpApplied():
        _reviveId = null;
        _retry = null;
        _kill(TripKillPoint.reviveBought);
        _applyRevive();
      case OpRefused(code: EconomyRefusal.alreadyRevived):
        _reviveId = null;
        _retry = null;
        if (_session?.engine.state.revivable ?? false) {
          _applyRevive();
        } else {
          _reviveHidden = true;
          _publish();
        }
      case OpRefused():
        _reviveId = null;
        _retry = null;
        _publish();
      case OpWriteFailed():
        _retry = TripRetry.revive;
        _publish();
    }
  }

  void _applyRevive() {
    final outcome = _command(
      const Revive(),
      phases: const {TripPhase.failed, TripPhase.opening},
    );
    if (outcome is Accepted && _session!.engine.status == TripStatus.running) {
      _setPhase(TripPhase.running);
    }
  }

  void pause(PauseReason reason) {
    final session = _session;
    if (_phase != TripPhase.running || session == null) return;
    session.engine.pause();
    _accumulator.clear();
    _breakMode = false;
    _pauseReason = reason;
    _saveClock();
    _setPhase(TripPhase.paused);
  }

  /// «كمّل المشوار»: disputes still open are asked first.
  void resume() {
    final session = _session;
    if (_phase != TripPhase.paused || session == null) return;
    _pauseReason = null;
    if (_disputes.isNotEmpty) return _setPhase(TripPhase.disputeOpen);
    session.engine.resume();
    _setPhase(TripPhase.running);
  }

  /// «ارجع الموقف»: records the trip abandoned (or failed) and goes Home.
  Future<void> leave() => _leave(const ExitToHome());

  /// A null [exit] records without leaving the screen (a restart).
  Future<bool> _leave(TripExit? exit) async {
    final session = _session;
    if (session == null) return false;
    if (_phase == TripPhase.paused || _phase == TripPhase.disputeOpen) {
      final outcome = _command(
        const Abandon(),
        phases: const {TripPhase.paused, TripPhase.disputeOpen},
        handleEnd: false,
      );
      if (outcome is! Accepted) return false;
      return _recordResult(session.engine.result!, exit: exit);
    }
    if (_phase == TripPhase.failed) {
      return _recordResult(session.engine.result!, exit: exit);
    }
    return false;
  }

  /// «عيد المشوار»: leaves this run, then starts the trip again.
  Future<void> restart() async {
    final tripId = _tripId;
    if (tripId == null || !_restartEnabled) return;
    if (!await _leave(null)) return;
    await _startAgain(tripId);
  }

  Future<void> _startAgain(String tripId) async {
    _session = null;
    _resetPlay();
    await open(tripId);
  }

  /// «حاول تاني» after a write failure.
  Future<void> retry() async {
    switch (_retry) {
      case TripRetry.start when _pendingStart != null:
        // Another trip started meanwhile: open from the top.
        if (!await _sendStart() && _tripId != null) await open(_tripId!);
      case TripRetry.result when _pendingResult != null:
        final pending = _pendingResult!;
        final recorded = await _recordResult(
          pending.result,
          exit: pending.exit,
          start: pending.start,
        );
        // No exit: a restart whose abandoned result failed goes on.
        if (recorded && pending.exit == null && _tripId != null) {
          await _startAgain(_tripId!);
        }
      case TripRetry.purchase:
        await buyBooster();
      case TripRetry.revive:
        await revive();
      default:
    }
  }

  // ---------------------------------------------------------------- Ending

  /// Records [result], deletes the record, then goes to [exit] (null: stay,
  /// for a restart).
  Future<bool> _recordResult(
    TripResult result, {
    required TripExit? exit,
    TxnId? start,
  }) async {
    final startTxn = start ?? _session!.startTxn;
    _pendingResult = _PendingResult(result, exit, start: startTxn);
    _retry = null;
    _setPhase(TripPhase.ending);
    // Every booster use is charged before the result closes the trip: the
    // economy takes none after it.
    if (!await _charge()) {
      _retry = TripRetry.result;
      _publish();
      return false;
    }
    final id = _resultId ??= _economy.newRequestId();
    final outcome = await _economy.recordResult(
      id,
      start: startTxn,
      result: result,
    );
    if (outcome is OpWriteFailed) {
      _retry = TripRetry.result;
      _publish();
      return false;
    }
    if (outcome case OpRefused(:final code)
        when code != EconomyRefusal.resultExists) {
      debugPrint('trip result refused: ${code.wire}');
    }
    _kill(TripKillPoint.resultRecorded);
    _resultId = null;
    _pendingResult = null;
    await _records.delete(startTxn);
    if (exit != null) _end(exit);
    return true;
  }

  TripExit _exitFor(TripResult result) => result.outcome == TripOutcome.finished
      ? ExitToResult(result.tripId, result)
      : const ExitToHome();

  void _end(TripExit exit) {
    _exit = exit;
    _setPhase(TripPhase.ended);
  }

  // ---------------------------------------------------------------- Inside

  /// Applies [command] at the current clock. Rejections change nothing but
  /// feedback.
  CommandOutcome? _command(
    Command command, {
    Set<TripPhase> phases = const {TripPhase.running},
    bool handleEnd = true,
  }) {
    final session = _session;
    if (session == null || !phases.contains(_phase) || _controlsLocked) {
      return null;
    }
    final engine = session.engine;
    final before = engine.state;
    final outcome = engine.apply(command);
    switch (outcome) {
      case Accepted(:final events):
        _write(
          _records.appendCommand(session.startTxn, engine.commandLog.last),
        );
        _absorb(events, before);
        if (handleEnd) _afterEvents(events);
        _publish();
      case Rejected(:final rejection):
        _reject(rejection.code);
    }
    return outcome;
  }

  void _reject(RejectionCode code) {
    final tMs = _session?.engine.state.tMs ?? 0;
    _emit(FeedbackCue(code));
    if (rejectionSpoken(code)) {
      _rejection = RejectionLine(code: code, untilMs: tMs + rejectionLineMs);
    }
    if (code == RejectionCode.commandLimit) {
      _controlsLocked = true;
      _breakMode = false;
    }
    _publish();
  }

  /// Folds [events] into the screen's memory and emits their cues.
  void _absorb(List<DomainEvent> events, TripState before) {
    final session = _session!;
    final after = session.engine.state;
    final cues = mapCues(
      events,
      before: before,
      after: after,
      facts: session.facts,
      speech: _speech(session),
    );
    // A bubble stays as long for the eye however fast the clock runs.
    _memory = _memory.update(
      events,
      cues,
      tMs: after.tMs,
      bubbleMinMs: session.facts.bubbleMinMs * _speed,
    );
    _takeHints(
      _hints.update(
        events,
        state: after,
        facts: session.facts,
        seen: _hintsSeen(),
      ),
    );
    cues.forEach(_emit);
  }

  /// The hints of those aboard as the trip opens or comes back.
  void _openHints() {
    final session = _session!;
    _takeHints(
      _hints.opened(
        state: session.engine.state,
        facts: session.facts,
        seen: _hintsSeen(),
      ),
    );
  }

  /// [hints] become the screen's, and the types they explain are saved.
  void _takeHints(HintState hints) {
    for (final wire in hints.explained.difference(_hints.explained)) {
      if (!_hintsSeen().contains(wire)) _onHintSeen?.call(wire);
    }
    _hints = hints;
  }

  /// What the engine's events change in the phase.
  void _afterEvents(List<DomainEvent> events) {
    final session = _session!;
    for (final event in events) {
      switch (event) {
        case DisputeRaised(:final disputeId):
          _disputes.add(disputeId);
        case TripFinished(:final result) || TripAbandoned(:final result):
          _saveClock();
          unawaited(_recordResult(result, exit: _exitFor(result)));
          return;
        case TripFailed():
          _saveClock();
          _accumulator.clear();
          _breakMode = false;
          _reviveHidden = false;
          _setPhase(TripPhase.failed);
          return;
        default:
      }
    }
    if (_disputes.isNotEmpty &&
        _phase == TripPhase.running &&
        session.engine.status == TripStatus.running) {
      session.engine.pause();
      _saveClock();
      _accumulator.clear();
      _breakMode = false;
      _setPhase(TripPhase.disputeOpen);
    }
  }

  SpeechResolver _speech(TripSession session) => SpeechResolver(
    pool: _content().speechPool,
    piasters: _piasters,
    station: (id) =>
        session.facts.stationName(id) ??
        _stationLetter(session.facts.slots[id] ?? 0),
  );

  ReviveOffer? _reviveOffer() {
    final state = _session?.engine.state;
    if (state == null || _reviveHidden) return null;
    return reviveOffer(
      state,
      priceBonat: _price(SkuKind.revive, BoosterId.revive),
      bonat: _economy.view.bonat,
      paid: _economy.view.unfinished?.revived ?? false,
    );
  }

  int? _price(SkuKind kind, BoosterId sku) {
    final price = _content().price(kind, wireOf(sku));
    return price?.currency == Currency.bonat ? price!.amount : null;
  }

  bool get _restartEnabled {
    final fuel = _economy.view.fuel;
    return fuel.liters > 0 || fuel.unlimitedUntilMs != null;
  }

  void _resetPlay() {
    _memory = PresentationMemory.empty;
    _hints = HintState.empty;
    _accumulator.clear();
    _breakMode = false;
    _controlsLocked = false;
    _rejection = null;
    _disputes.clear();
    _disabledBoosters.clear();
    _boosterCard = null;
    _pauseReason = null;
    _reviveHidden = false;
  }

  void _setPhase(TripPhase phase) {
    _phase = phase;
    if (phase != TripPhase.running) _accumulator.clear();
    _publish();
  }

  /// How many times faster than real time the trip clock runs.
  int get _speed =>
      _phase == TripPhase.running && (_session?.engine.isSettled ?? false)
      ? settledSpeedUp
      : 1;

  void _publish() {
    if (_disposed) return;
    final session = _session;
    final view = session == null
        ? null
        : projectTripView(
            session.engine.state,
            _memory,
            session.facts,
            TripScreenState(
              phase: _phase,
              breakMode: _breakMode,
              controlsLocked: _controlsLocked,
              inventory: _stock(),
              boosterPrices: {
                for (final b in tripBoosters) b: ?_price(SkuKind.booster, b),
              },
              disabledBoosters: _disabledBoosters,
              revive: _phase == TripPhase.failed ? _reviveOffer() : null,
              rejection: _rejection,
              fastForward: _speed > 1,
            ),
            hint: _hints.showing,
            dispute: _phase == TripPhase.disputeOpen && _disputes.isNotEmpty
                ? _disputes.first
                : null,
          );
    final booster = _boosterCard;
    final model = TripModel(
      phase: _phase,
      view: view,
      retry: _retry,
      nextLiterAtMs: _phase == TripPhase.noFuel ? _nextLiterAtMs : null,
      exit: _phase == TripPhase.ended ? _exit : null,
      boosterCard: _phase == TripPhase.boosterCard && booster != null
          ? BoosterCardModel(
              booster: booster,
              priceBonat: _price(SkuKind.booster, booster),
              bonat: _economy.view.bonat,
              shortBy: _boosterShortBy,
            )
          : null,
      pauseReason: _phase == TripPhase.paused ? _pauseReason : null,
      restartEnabled:
          (_phase == TripPhase.paused || _phase == TripPhase.failed) &&
          _restartEnabled,
    );
    if (model == _model) return;
    _model = model;
    _models.add(model);
  }

  void _emit(TripCue cue) {
    if (!_disposed) _cues.add(cue);
  }

  /// Saves the record's clock where the engine stopped, so a kill rebuilds
  /// the trip at that moment (every pause, a dispute, a failure, the end).
  void _saveClock() {
    final session = _session;
    if (session == null) return;
    _write(_records.saveClock(session.startTxn, session.engine.state.tMs));
  }

  /// A record write the trip doesn't wait for. A failure stays queued in
  /// the store and lands with the next write.
  void _write(Future<bool> write) {
    unawaited(
      write.then<void>(
        (_) {},
        onError: (Object error) => debugPrint('trip record write: $error'),
      ),
    );
  }

  void _kill(TripKillPoint point) => onKillPoint?.call(point);

  /// The ads seam: asked only while the engine is paused or failed.
  @visibleForTesting
  TripAdOffers get ads => _ads;

  /// Saves the clock if the trip is still running, then stops.
  void dispose() {
    if (_disposed) return;
    final session = _session;
    if (session != null && _phase == TripPhase.running) {
      session.engine.pause();
      _saveClock();
    }
    _disposed = true;
    unawaited(_models.close());
    unawaited(_cues.close());
    _frames.dispose();
  }
}

/// The result of an unfinished trip whose record is gone: the pack's trip
/// abandoned at once, or, without the trip, the same result written out.
TripResult abandonedResult(
  String tripId,
  TripDefinition? definition,
  TripParams Function(TripDefinition definition) params,
) {
  if (definition != null) {
    final engine = TripEngine.start(definition, params(definition))
      ..apply(const Abandon());
    return engine.result!;
  }
  return TripResult.fromJson({
    'trip_id': tripId,
    'rev': 1,
    'outcome': 'abandoned',
    'stars': 0,
    'star_flags': {'reached': false, 'no_fights': true, 'no_mistakes': true},
    'fares_collected_piasters': 0,
    'overpaid_piasters': 0,
    'tips_piasters': 0,
    'earnings_jenehat': 0,
    'fights': 0,
    'lost_fares': 0,
    'missed_stops': 0,
    'impatient': 0,
    'caught_liars': 0,
    'mistakes': <Object>[],
    'reputation': 100,
    'reputation_lost': <String, Object>{},
    'duration_ms': 0,
    'boosters_used': <Object>[],
    'revived': false,
    'command_log_hash': commandLogHash(const [LoggedCommand(0, Abandon())]),
  });
}

final class _PendingStart {
  _PendingStart({required this.header, required this.facts});

  final TripRecordHeader header;
  final TripFacts facts;
  bool written = false;
}

/// A booster use and its record's write, which its charge waits for
/// (research R7).
final class _Use {
  _Use(this.intent, this.written);

  final TripIntent intent;
  final Future<void> written;

  /// The charge in flight, if any.
  Future<void>? charging;
}

final class _PendingResult {
  const _PendingResult(this.result, this.exit, {required this.start});

  final TripResult result;
  final TripExit? exit;
  final TxnId start;
}
