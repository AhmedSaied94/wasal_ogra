// Trip screen test helpers (specs/008-m02-trip-screen/tasks.md T005): the
// sample pack's trips and lines, the bundled params, the parity fixtures,
// and the fakes for the trip's platform edges.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:content_models/content_models.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/bootstrap/flavor.dart';
import 'package:wassal/core/audio_haptics/audio_haptics_providers.dart';
import 'package:wassal/core/audio_haptics/haptics.dart';
import 'package:wassal/core/config/bundled_config_source.dart';
import 'package:wassal/core/config/config_source.dart';
import 'package:wassal/core/content/domain/content_source.dart';
import 'package:wassal/core/economy/economy.dart'
    show Economy, EconomyState, EconomyView, FuelState, OpOutcome, TxnId;
import 'package:wassal/core/economy/economy_providers.dart';
import 'package:wassal/core/preferences/settings_store.dart';
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/core/l10n/number_formatter.dart';
import 'package:wassal/features/trip/application/trip_controller.dart';
import 'package:wassal/features/trip/data/drift_trip_records.dart';
import 'package:wassal/features/trip/data/trip_kill_point.dart';
import 'package:wassal/features/trip/data/trip_records.dart';
import 'package:wassal/core/audio_haptics/sfx.dart';
import 'package:wassal/core/economy/domain/op.dart' show AdPlacement;
import 'package:wassal/features/trip/application/trip_ad_offers.dart';
import 'package:wassal/features/trip/application/trip_settings.dart';
import 'package:wassal/features/trip/domain/cues.dart';
import 'package:wassal/features/trip/domain/presentation_memory.dart';
import 'package:wassal/features/trip/domain/projection.dart';
import 'package:wassal/features/trip/domain/speech.dart';
import 'package:wassal/features/trip/domain/trip_facts.dart';
import 'package:wassal/features/trip/domain/step_accumulator.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';
import 'package:wassal/features/trip/application/trip_phase.dart';
import 'package:wassal/features/trip/presentation/cards/failure_card.dart';
import 'package:wassal/features/trip/presentation/cards/pause_card.dart';
import 'package:wassal/features/trip/presentation/dashboard/boosters_row.dart';
import 'package:wassal/features/trip/presentation/dashboard/hand_slot.dart';
import 'package:wassal/features/trip/presentation/dashboard/tray.dart';
import 'package:wassal/features/trip/presentation/overlays/choices_layer.dart';
import 'package:wassal/features/trip/presentation/overlays/token_layer.dart';
import 'package:wassal/features/trip/presentation/overlays/hit_areas.dart';
import 'package:wassal/features/trip/presentation/dashboard/dashboard.dart';
import 'package:wassal/core/art/rive_art.dart';
import 'package:wassal/features/trip/presentation/scene/svg_passenger_art.dart';
import 'package:wassal/features/trip/presentation/top_bar/top_bar.dart';
import 'package:wassal/features/trip/presentation/trip_scope.dart';
import 'package:wassal/features/trip/trip_providers.dart';

import '../design/design_check.dart';
import 'economy.dart';
import 'memory_settings_store.dart';
import 'pump_app.dart';

const _sample = '../../content/examples/sample';
const _fixtures = '../../fixtures/parity';

Map<String, dynamic> _json(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

/// A sample trip's definition, such as `line_hay.01`.
TripDefinition sampleTrip(String tripId) => TripDefinition.fromJson(
  _json('$_sample/trips/${tripId.split('.').first}/$tripId.json'),
);

/// A sample line, by wire name.
Line sampleLine(String lineId) =>
    Line.fromJson(_json('$_sample/lines/$lineId.json'));

/// The bundled params of [line].
TripParams bundledParams(LineId line) =>
    TripParams.fromTunables(bundledTunables(), line);

/// The sample trips, by id.
const sampleTripIds = [
  'line_hay.01',
  'line_hay.02',
  'line_hay.03',
  'line_gamaa.01',
  'line_gamaa.02',
];

/// Facts for [definition] with the bundled params and its sample line.
TripFacts factsFor(
  TripDefinition definition, {
  bool withLine = true,
  HintMode hintMode = HintMode.off,
  int bubbleMinMs = 4000,
  TripParams? params,
}) {
  final lineWire = definition.tripId.split('.').first;
  return TripFacts(
    definition: definition,
    line: withLine ? sampleLine(lineWire) : null,
    params: params ?? bundledParams(definition.lineId),
    bubbleMinMs: bubbleMinMs,
    hintMode: hintMode,
  );
}

/// The view of [engine] with an empty memory, running.
TripView viewOf(
  TripEngine engine,
  TripFacts facts, {
  PresentationMemory memory = PresentationMemory.empty,
  TripScreenState screen = const TripScreenState(phase: TripPhase.running),
}) => projectTripView(engine.state, memory, facts, screen);

/// A parity fixture, by file name without `.json`.
ParityFixture loadFixture(String name) => ParityFixture.fromJson(
  jsonDecode(File('$_fixtures/$name.json').readAsStringSync()),
);

/// Every fixture's name, sorted.
List<String> allFixtureNames() => [
  for (final file in Directory(_fixtures).listSync().whereType<File>())
    if (file.path.endsWith('.json'))
      file.uri.pathSegments.last.replaceFirst('.json', ''),
]..sort();

/// Plays [fixture] on the engine as a replay does, folding every moment
/// into the screen's memory as the controller does. [check] runs after
/// each command and each step, with that moment's events.
void playWithMemory(
  ParityFixture fixture,
  void Function(TripState state, TripView view, List<DomainEvent> events) check,
) {
  final facts = factsFor(
    fixture.definition,
    params: fixture.params,
    withLine: false,
  );
  final content = sampleContent();
  final speech = SpeechResolver(
    pool: content.speechPool,
    piasters: (p) => '$p',
    station: (id) => id,
  );
  final engine = TripEngine.start(
    fixture.definition,
    fixture.params,
    seed: fixture.seed,
  );
  var memory = PresentationMemory.empty;

  void fold(TripState before, List<DomainEvent> events) {
    final after = engine.state;
    final cues = mapCues(
      events,
      before: before,
      after: after,
      facts: facts,
      speech: speech,
    );
    memory = memory.update(
      events,
      cues,
      tMs: after.tMs,
      bubbleMinMs: facts.bubbleMinMs,
    );
    final screen = TripScreenState(
      phase: switch (after.status) {
        TripStatus.failed => TripPhase.failed,
        _ => TripPhase.running,
      },
    );
    check(after, projectTripView(after, memory, facts, screen), events);
  }

  void step() {
    final before = engine.state;
    fold(before, engine.step());
  }

  for (final entry in fixture.commandLog) {
    while (engine.state.tMs < entry.tMs &&
        engine.status == TripStatus.running) {
      step();
    }
    final before = engine.state;
    final outcome = engine.apply(entry.command);
    fold(before, outcome is Accepted ? outcome.events : const []);
  }
  while (engine.status == TripStatus.running) {
    step();
  }
}

/// The trip screen's test frames, in logical points, each with the status
/// bar the phone reports (specs/008.5-m21-design-refresh,
/// contracts/trip-layout.md "Golden surfaces"). M03's [Surface] stays as it
/// is. [compliant] surfaces keep every minimum size; [small] is the
/// exception, where only the scene's faces shrink.
enum TripSurface {
  reference(Size(390, 844), inset: designTopInset, compliant: true),
  a06(Size(360, 800), inset: 24, compliant: true),
  small(Size(360, 640), inset: 24, compliant: false);

  const TripSurface(this.size, {required this.inset, required this.compliant});

  final Size size;
  final double inset;
  final bool compliant;
}

void applyTripSurface(WidgetTester tester, TripSurface surface) =>
    applyDesignSurface(tester, surface.size, topInset: surface.inset);

/// Records every effect played, in order.
final class FakeSfxPlayer implements SfxPlayer {
  final played = <Sfx>[];
  bool loaded = false;

  @override
  Future<void> load() async => loaded = true;

  @override
  void play(Sfx sfx) => played.add(sfx);

  @override
  Future<void> dispose() async {}
}

/// Records every vibration, in order.
final class FakeHaptics implements Haptics {
  final felt = <String>[];

  @override
  void light() => felt.add('light');

  @override
  void heavy() => felt.add('heavy');

  @override
  void selection() => felt.add('selection');
}

/// A settings store holding the trip's preferences.
MemorySettingsStore tripSettingsStore({
  bool sound = true,
  bool haptics = true,
  Set<String> hintsSeen = const {},
}) => MemorySettingsStore({
  tripSoundKey: sound ? 'on' : 'off',
  tripHapticsKey: haptics ? 'on' : 'off',
  tripHintsSeenKey: (hintsSeen.toList()..sort()).join(','),
});

/// Never offers, and fails the test if it is asked while the engine runs
/// (constitution IX).
final class SpyTripAdOffers implements TripAdOffers {
  SpyTripAdOffers({required this.engineStatus});

  /// The engine's status when asked.
  final TripStatus? Function() engineStatus;
  final calls = <AdPlacement>[];

  void _check(AdPlacement placement) {
    calls.add(placement);
    if (engineStatus() == TripStatus.running) {
      fail('$placement asked while the trip runs');
    }
  }

  @override
  bool isOffered(AdPlacement placement) {
    _check(placement);
    return false;
  }

  @override
  Future<bool> show(AdPlacement placement) async {
    _check(placement);
    return false;
  }
}

/// The bundled tunables as a config source.
ConfigSource bundledConfig() => BundledConfigSource(bundledTunables());

/// [inner] with [extra] trips in place of its own (a fixture's definition
/// under a sample trip id, say) and [hidden] trips gone.
final class TripContent implements ContentSource {
  TripContent(
    this.inner, {
    List<TripDefinition> extra = const [],
    this.hidden = const {},
  }) : _extra = {for (final t in extra) t.tripId: t};

  final ContentSource inner;
  final Map<String, TripDefinition> _extra;
  final Set<String> hidden;

  @override
  TripDefinition? trip(String tripId) =>
      hidden.contains(tripId) ? null : _extra[tripId] ?? inner.trip(tripId);

  @override
  List<TripDefinition> tripsOf(LineId line) => [
    for (final t in inner.tripsOf(line)) ?trip(t.tripId),
  ];

  @override
  int get version => inner.version;
  @override
  List<Line> get lines => inner.lines;
  @override
  Line? line(LineId id) => inner.line(id);
  @override
  List<Vehicle> get vehicles => inner.vehicles;
  @override
  Vehicle? vehicle(VehicleId id) => inner.vehicle(id);
  @override
  CatalogPrice? price(SkuKind kind, String skuId) => inner.price(kind, skuId);
  @override
  SpeechPool? speechPool(String speechKey) => inner.speechPool(speechKey);
  @override
  List<Chapter> get chapters => inner.chapters;
  @override
  Chapter? chapter(ChapterId id) => inner.chapter(id);
  @override
  List<Room> get rooms => inner.rooms;
  @override
  Room? room(RoomId id) => inner.room(id);
  @override
  List<Item> itemsOf(RoomId room) => inner.itemsOf(room);
  @override
  Item? item(String itemId) => inner.item(itemId);
  @override
  List<FamilyRequest> get familyRequests => inner.familyRequests;
  @override
  List<DailyRewardDay> get dailyRewards => inner.dailyRewards;
  @override
  List<TaskTemplate> get tasks => inner.tasks;
}

/// The station letters the screen uses, for tests without l10n.
String testStationLetter(int slot) => const ['أ', 'ب', 'ج', 'د'][slot % 4];

/// A controller over [economy]'s database and content, with the bundled
/// tunables.
TripController testController(
  TestEconomy economy, {
  Economy? service,
  TripRecords? records,
  ContentSource Function()? content,
  FixedTrip? fixed,
  TripAdOffers ads = const NoTripAdOffers(),
  void Function(TripKillPoint point)? onKillPoint,
  Set<String> Function()? hintsSeen,
  void Function(String wire)? onHintSeen,
  DigitStyle digits = DigitStyle.western,
  bool disposeAtTearDown = true,
}) {
  final controller = TripController(
    economy: service ?? economy.service,
    content: content ?? () => economy.content,
    contentVersion: () => 1,
    config: bundledConfig,
    records: records ?? DriftTripRecords(economy.db, onKillPoint: onKillPoint),
    piasters: NumberFormatter(digits).piasters,
    stationLetter: testStationLetter,
    hintsSeen: hintsSeen,
    onHintSeen: onHintSeen,
    ads: ads,
    onKillPoint: onKillPoint,
    fixedTrip: fixed,
  );
  // A killed controller is never disposed: its process is gone.
  if (disposeAtTearDown) addTearDown(controller.dispose);
  return controller;
}

/// [inner], except where a test scripts what `startTrip`, `useBooster` or
/// `buy` come to: a hook returns an outcome of its own, or null to go
/// through.
final class ScriptedEconomy implements Economy {
  ScriptedEconomy(
    this.inner, {
    this.onStartTrip,
    this.onUseBooster,
    this.onBuy,
  });

  final Economy inner;
  Future<OpOutcome>? Function(TxnId id, String tripId)? onStartTrip;
  Future<OpOutcome>? Function(TxnId id, BoosterId booster)? onUseBooster;
  Future<OpOutcome>? Function(TxnId id, SkuKind kind, String skuId)? onBuy;

  @override
  EconomyView get view => inner.view;

  @override
  Stream<EconomyView> get views => inner.views;

  @override
  TxnId newRequestId() => inner.newRequestId();

  @override
  Future<OpOutcome> startTrip(TxnId id, {required String tripId}) =>
      onStartTrip?.call(id, tripId) ?? inner.startTrip(id, tripId: tripId);

  @override
  Future<OpOutcome> recordResult(
    TxnId id, {
    required TxnId start,
    required TripResult result,
  }) => inner.recordResult(id, start: start, result: result);

  @override
  Future<OpOutcome> useBooster(TxnId id, {required BoosterId booster}) =>
      onUseBooster?.call(id, booster) ?? inner.useBooster(id, booster: booster);

  @override
  Future<OpOutcome> buy(
    TxnId id, {
    required SkuKind kind,
    required String skuId,
    String? variantId,
  }) =>
      onBuy?.call(id, kind, skuId) ??
      inner.buy(id, kind: kind, skuId: skuId, variantId: variantId);

  @override
  Future<OpOutcome> applyAdReward(TxnId id, {required AdPlacement placement}) =>
      inner.applyAdReward(id, placement: placement);
}

/// Advances [controller] by [ms] on the trip clock, one step a frame.
void advanceMs(TripController controller, int ms) {
  for (var t = 0; t < ms; t += 33) {
    controller.advance(const Duration(milliseconds: 33));
  }
}

/// Advances until the phase leaves running, at most [ms].
void runOut(TripController controller, {int ms = 600000}) {
  for (var t = 0; t < ms && controller.phase == TripPhase.running; t += 33) {
    controller.advance(const Duration(milliseconds: 33));
  }
}

/// Lets the writes the controller doesn't wait for land.
Future<void> settle() => pumpEventQueue(times: 50);

/// How many rows [table] holds.
Future<int> rowCount(TestEconomy economy, String table) async =>
    (await economy.db
            .customSelect('SELECT COUNT(*) AS n FROM $table')
            .getSingle())
        .read<int>('n');

/// How many ops of [opType] the economy's log holds.
Future<int> opCount(TestEconomy economy, String opType) async =>
    (await economy.db
            .customSelect(
              'SELECT COUNT(*) AS n FROM ledger_ops WHERE op_type = ?',
              variables: [Variable.withString(opType)],
            )
            .getSingle())
        .read<int>('n');

/// Plays [commands] through [controller]'s intents at their times; an
/// open dispute takes the log's answer.
Future<void> playCommands(
  TripController controller,
  Iterable<LoggedCommand> commands,
) async {
  for (final entry in commands) {
    while (controller.engine!.state.tMs < entry.tMs &&
        controller.phase == TripPhase.running) {
      controller.advance(const Duration(milliseconds: engineStepMs));
    }
    switch (entry.command) {
      case PickFromTray(:final denomination):
        controller.pick(denomination);
      case ReturnHand():
        controller.returnHand();
      case SendHand(:final passengerId):
        controller.send(passengerId);
      case UndoLastSend():
        controller.undo();
      case Tap(:final passengerId):
        controller.tap(passengerId);
      case ResolveClaim(:final passengerId, :final insist):
        controller.answerClaim(passengerId, insist: insist);
      case ResolveDispute(:final paidPassengerId):
        controller.answerDispute(paidPassengerId);
      case ResolveChangeRequest(:final passengerId, :final agree):
        controller.answerChangeRequest(passengerId, agree: agree);
      case RequestBreak(:final denomination):
        controller
          ..startBreak()
          ..pickBreak(denomination);
      case CollectDropped(:final tokenId):
        controller.collect(tokenId);
      case UseBooster(:final booster):
        await controller.useBooster(booster);
      case Revive():
        await controller.revive();
      case Abandon():
        await controller.leave();
    }
  }
}

/// The economy as an [Economy], for code typed on the interface.
Economy economyOf(TestEconomy economy) => economy.service;

/// The trip screen's platform edges as fakes, for every app test: no
/// sound or vibration plugins, no Rive file (the static art everywhere), no
/// ads, and a
/// clock the test moves itself (the scene steps once per change).
List<Override> tripTestOverrides({
  FakeSfxPlayer? sfx,
  FakeHaptics? haptics,
  TripAdOffers ads = const NoTripAdOffers(),
}) => [
  sfxPlayerProvider.overrideWithValue(sfx ?? FakeSfxPlayer()),
  hapticsProvider.overrideWithValue(haptics ?? FakeHaptics()),
  tripFrameDrivenProvider.overrideWithValue(false),
  riveArtProvider.overrideWith((ref) async => const RiveArt.none()),
  passengerArtProvider.overrideWithValue(const SvgPassengerArtFactory()),
  tripAdOffersProvider.overrideWithValue(ads),
];

/// The app's economy over [economy], a [testEconomy] (seeded with
/// `firstState` when a test needs boosters or BONAT).
List<Override> economyOverridesOf(TestEconomy economy) => [
  uptimeSourceProvider.overrideWithValue(economy.uptime),
  appDatabaseProvider.overrideWith((ref) async => economy.db),
  economyStoreProvider.overrideWith((ref) async => economy.store),
  trustedClockProvider.overrideWith((ref) async => economy.clock),
  economyProvider.overrideWith((ref) {
    // Its fuel timer stops with the app, as the real provider's does.
    ref.onDispose(economy.service.dispose);
    return economy.service;
  }),
  tripRecordsProvider.overrideWithValue(DriftTripRecords(economy.db)),
];

/// Pumps the app on the trip screen of [tripId], on [surface]. [fixed]
/// Decodes the passengers' static art for real, outside the fake clock, so
/// the first frame draws them.
Future<void> preloadTripArt(WidgetTester tester) =>
    tester.runAsync(SvgPassengerArtFactory.preload);

/// opens a fixture's trip instead of the pack's (the scripted player).
Future<ProviderContainer> pumpTrip(
  WidgetTester tester, {
  String tripId = 'line_hay.01',
  TripSurface surface = TripSurface.reference,
  DigitStyle digits = DigitStyle.arabicIndic,
  double textScale = 1.0,
  TestEconomy? economy,
  FixedTrip? fixed,
  FakeSfxPlayer? sfx,
  FakeHaptics? haptics,
  TripAdOffers ads = const NoTripAdOffers(),
  SettingsStore? settingsStore,
  Flavor flavor = Flavor.dev,
  List<Override> overrides = const [],
  bool settle = true,
}) async {
  applyTripSurface(tester, surface);
  await preloadTripArt(tester);
  return pumpWassalApp(
    tester,
    flavor: flavor,
    settle: settle,
    size: surface.size,
    digits: digits,
    textScale: textScale,
    settingsStore: settingsStore,
    economy: economy == null ? null : economyOverridesOf(economy),
    initialLocation: '/trip/$tripId',
    trip: tripTestOverrides(sfx: sfx, haptics: haptics, ads: ads),
    overrides: [
      if (fixed != null) tripFixedProvider.overrideWithValue(fixed),
      ...overrides,
    ],
  );
}

/// The controller of the trip screen on screen.
TripController controllerOf(WidgetTester tester) => tester
    .element(find.byType(TripDashboard))
    .getInheritedWidgetOfExactType<TripScope>()!
    .controller;

/// An economy that can pay for everything [fixture]'s log uses: each
/// booster as many times as the log uses it, and BONAT for each revive at
/// the catalog price, so no purchase card changes the log's timing. A
/// trip the pack lacks (the stress fixture's) is added to it.
Future<TestEconomy> economyFor(ParityFixture fixture) {
  final pack = sampleContent();
  final definition = fixture.definition;
  final ContentSource content = pack.trip(definition.tripId) == null
      ? TripContent(pack, extra: [definition])
      : pack;
  final boosters = <BoosterId, int>{};
  var revives = 0;
  for (final entry in fixture.commandLog) {
    switch (entry.command) {
      case UseBooster(:final booster):
        boosters[booster] = (boosters[booster] ?? 0) + 1;
      case Revive():
        revives++;
      default:
    }
  }
  final revivePrice = content.price(SkuKind.revive, 'revive')?.amount ?? 0;
  return testEconomy(
    content: content,
    firstState: (nowMs) => EconomyState.newPlayer(
      fuelMax: 5,
      nowMs: nowMs,
    ).copyWith(inventory: boosters, bonat: revives * revivePrice),
  );
}

/// What a scripted run ended with.
final class ScriptedRun {
  const ScriptedRun({
    required this.exit,
    required this.result,
    required this.inexact,
  });

  final TripExit? exit;

  /// The engine's result as the trip ended: finished, failed (left from
  /// the failure card) or abandoned.
  final TripResult? result;

  /// A dispute was answered without the log's answer: the result can't
  /// be compared.
  final bool inexact;
}

/// Plays [fixture] through the trip screen's controls (tasks.md T034): it
/// opens the fixture's trip, and for each logged command advances the
/// clock to its time and makes the matching gesture, then runs the trip
/// out.
final class ScriptedPlayer {
  ScriptedPlayer(this.tester, this.fixture, {this.onFrame});

  final WidgetTester tester;
  final ParityFixture fixture;

  /// Runs after every frame the player pumps; with it, the player also
  /// pumps every [_frameEveryMs] of trip time between commands.
  final Future<void> Function()? onFrame;
  bool _inexact = false;

  static const _frameEveryMs = 10 * engineStepMs;

  Future<void> _frame({bool timed = false}) async {
    final frame = onFrame;
    if (frame == null) return;
    if (timed) {
      final tMs = controllerOf(tester).engine!.state.tMs;
      if (tMs % _frameEveryMs != 0) return;
      await tester.pump();
    }
    await frame();
  }

  /// Opens the fixture's trip on [economy], [economyFor]'s by default.
  Future<ScriptedRun> play({
    TripSurface surface = TripSurface.reference,
    TestEconomy? economy,
  }) async {
    economy ??= await economyFor(fixture);
    await pumpTrip(
      tester,
      tripId: fixture.definition.tripId,
      surface: surface,
      economy: economy,
      fixed: FixedTrip(
        definition: fixture.definition,
        params: fixture.params,
        seed: fixture.seed,
      ),
    );
    return drive();
  }

  /// Plays the trip already on screen; [settle] waits for the result to be
  /// recorded (the real database needs real time).
  Future<ScriptedRun> drive({Future<void> Function()? settle}) async {
    final controller = controllerOf(tester);
    for (final entry in fixture.commandLog) {
      await _advanceTo(controller, entry.tMs);
      expect(
        controller.engine!.state.tMs,
        entry.tMs,
        reason: 'clock at ${entry.command}',
      );
      await tester.pump();
      await _frame();
      await _perform(controller, entry.command);
      await tester.pump();
      await _frame();
    }
    await _runOut(controller);
    final result = controller.engine?.result;
    // A trip that ends failed is left from its card.
    if (controller.phase == TripPhase.failed) {
      await tester.pump();
      await _tap(find.byKey(FailureCard.homeKey));
    }
    await (settle?.call() ?? tester.pumpAndSettle());
    return ScriptedRun(
      exit: controller.model.exit,
      result: result,
      inexact: _inexact,
    );
  }

  Future<void> _advanceTo(TripController controller, int tMs) async {
    while (controller.engine!.state.tMs < tMs) {
      if (controller.phase == TripPhase.disputeOpen) {
        await _answerDispute(controller);
        continue;
      }
      expect(controller.phase, TripPhase.running);
      controller.advance(oneStep(controller));
      await _frame(timed: true);
    }
  }

  Future<void> _runOut(TripController controller) async {
    for (var guard = 0; guard < 100000; guard++) {
      switch (controller.phase) {
        case TripPhase.running:
          controller.advance(oneStep(controller));
          await _frame(timed: true);
        case TripPhase.disputeOpen:
          await _answerDispute(controller);
        default:
          return;
      }
    }
  }

  /// The log's answer to the dispute being asked, or its first candidate.
  Future<void> _answerDispute(TripController controller) async {
    final choice = controller.view!.choices.whereType<DisputeChoice>().first;
    final logged = fixture.commandLog
        .map((e) => e.command)
        .whereType<ResolveDispute>()
        .where((c) => c.disputeId == choice.disputeId)
        .firstOrNull;
    if (logged == null) _inexact = true;
    controller.answerDispute(logged?.paidPassengerId ?? choice.a);
    await tester.pump();
  }

  Future<void> _perform(TripController controller, Command command) async {
    switch (command) {
      case PickFromTray(:final denomination):
        await _tap(find.byKey(Tray.slotKey(denomination)));
      case ReturnHand():
        await _tap(find.byKey(HandSlot.slotKey));
      case SendHand(:final passengerId):
        expect(controller.view!.hand.isEmpty, isFalse);
        await _tap(find.byKey(HitAreas.keyOf(passengerId)));
      case Tap(:final passengerId):
        expect(controller.view!.hand.isEmpty, isTrue);
        await _tap(find.byKey(HitAreas.keyOf(passengerId)));
      case UndoLastSend():
        await _tap(find.byKey(UndoButton.buttonKey));
      case ResolveClaim(:final passengerId, :final insist):
        await _tap(
          find.byKey(ChoicesLayer.claimKey(passengerId, insist: insist)),
        );
      case ResolveChangeRequest(:final passengerId, :final agree):
        await _tap(
          find.byKey(ChoicesLayer.changeRequestKey(passengerId, agree: agree)),
        );
      case CollectDropped(:final tokenId):
        await _tap(find.byKey(DroppedLayer.noteKey(tokenId)));
      case RequestBreak(:final denomination):
        await _tap(find.byKey(CallChangeButton.buttonKey));
        await tester.pump();
        expect(controller.view!.breakMode, isTrue);
        await _tap(find.byKey(Tray.slotKey(denomination)));
      case UseBooster(:final booster):
        // The economy holds what the log uses (economyFor): no card.
        final used = controller.engine!.state.boostersUsed.length;
        await _tap(find.byKey(BoostersRow.slotKey(booster)));
        expect(controller.engine!.state.boostersUsed, hasLength(used + 1));
        expect(controller.phase, TripPhase.running);
      case Revive():
        expect(controller.phase, TripPhase.failed);
        await tester.pump();
        await _tap(find.byKey(FailureCard.reviveKey));
        // Paid first: the engine revives when the economy answers.
        await tester.pumpAndSettle();
        expect(controller.engine!.state.revived, isTrue);
      case Abandon():
        await _tap(find.byKey(TripHud.pauseKey));
        await tester.pump();
        await _tap(find.byKey(PauseCard.homeKey));
      case ResolveDispute():
        // The dispute rule answers it when it opens.
        if (controller.phase == TripPhase.disputeOpen) {
          await _answerDispute(controller);
        }
    }
  }

  Future<void> _tap(Finder target) async {
    expect(target, findsOneWidget);
    await tester.tap(target, warnIfMissed: false);
  }
}

/// Plays the trip on screen to its end with [fixture]'s log, through the
/// controller; the screen's trip must be the fixture's.
Future<void> finishTrip(
  WidgetTester tester, {
  String fixture = 'sample__line_hay_01_three_stars',
}) async {
  final controller = controllerOf(tester);
  for (final entry in loadFixture(fixture).commandLog) {
    while (controller.engine!.state.tMs < entry.tMs) {
      controller.advance(oneStep(controller));
    }
    switch (entry.command) {
      case PickFromTray(:final denomination):
        controller.pick(denomination);
      case ReturnHand():
        controller.returnHand();
      case SendHand(:final passengerId):
        controller.send(passengerId);
      case Tap(:final passengerId):
        controller.tap(passengerId);
      case UndoLastSend():
        controller.undo();
      default:
        fail('finishTrip has no call for ${entry.command}');
    }
  }
  while (controller.phase == TripPhase.running) {
    controller.advance(oneStep(controller));
  }
  await tester.pumpAndSettle();
}

/// A trip screen state that the goldens and the size checks render
/// (tasks.md T042, T043).
final class TripCase {
  const TripCase(
    this.name, {
    this.tripId = 'line_hay.01',
    this.emptyTank = false,
    this.lastLiter = false,
    this.fixture,
    this.economy,
    this.prepare,
  });

  final String name;
  final String tripId;

  /// The economy to open on, in place of a new player's.
  final Future<TestEconomy> Function()? economy;

  /// Opens this fixture's trip instead of [tripId].
  final String? fixture;
  final bool emptyTank;

  /// One liter left, which the trip's start spends.
  final bool lastLiter;
  final Future<void> Function(WidgetTester tester, TripController c)? prepare;
}

/// A frame that moves [controller]'s trip clock exactly one step, however
/// fast it runs (`settledSpeedUp` times once nothing is left), so a log's
/// commands land on their exact times.
Duration oneStep(TripController controller) => Duration(
  microseconds:
      engineStepMs *
      1000 ~/
      ((controller.view?.fastForward ?? false) ? settledSpeedUp : 1),
);

/// Advances [c] until [reached] holds, then draws the frame.
Future<void> untilView(
  WidgetTester tester,
  TripController c,
  bool Function(TripView view) reached, {
  int maxMs = 180000,
}) async {
  for (var t = 0; t < maxMs && !reached(c.view!); t += engineStepMs) {
    c.advance(const Duration(milliseconds: engineStepMs));
  }
  expect(reached(c.view!), isTrue, reason: 'state never reached');
  await tester.pump();
}

/// The US1 states: idle on both vehicles, money in transit, two bubbles,
/// a station warning, and the empty tank.
List<TripCase> us1TripCases() => [
  const TripCase('idle_tuktuk'),
  const TripCase('idle_micro_old', tripId: 'line_gamaa.02'),
  TripCase(
    'transit',
    prepare: (tester, c) => untilView(
      tester,
      c,
      (v) => v.tokens.any((t) => t.hopMs > 0 && t.progressPermille >= 400),
    ),
  ),
  TripCase(
    'two_bubbles',
    tripId: 'line_gamaa.02',
    prepare: (tester, c) => untilView(tester, c, (v) => v.bubbles.length >= 2),
  ),
  TripCase(
    'station_warning',
    prepare: (tester, c) => untilView(tester, c, (v) => v.strip.warning),
  ),
  const TripCase('no_fuel', emptyTank: true),
];

/// The US2 states: the pause card, with and without a liter to restart.
List<TripCase> us2TripCases() => [
  const TripCase('paused', prepare: _pauseAfter),
  const TripCase('paused_empty_tank', lastLiter: true, prepare: _pauseAfter),
];

/// The US3 states: what the archetypes show, and a claim's answers.
List<TripCase> us3TripCases() => [
  TripCase(
    'blocked_token',
    fixture: 'archetype__sleeper_blocks_chain',
    prepare: (tester, c) =>
        untilView(tester, c, (v) => v.tokens.any((t) => t.blocked)),
  ),
  TripCase(
    'sleeper',
    fixture: 'archetype__sleeper_missed_stop',
    prepare: (tester, c) =>
        untilView(tester, c, (v) => v.passengers.any((p) => p.asleep)),
  ),
  TripCase(
    'headphones',
    fixture: 'archetype__headphones_called_twice',
    prepare: (tester, c) =>
        untilView(tester, c, (v) => v.passengers.any((p) => p.headphones)),
  ),
  TripCase(
    'claim',
    fixture: 'archetype__false_claimer_believed',
    prepare: (tester, c) => untilView(
      tester,
      c,
      (v) => v.choices.whereType<ClaimChoice>().isNotEmpty,
    ),
  ),
  TripCase(
    'near_stop_pulse',
    fixture: 'core__fight_at_stop',
    prepare: (tester, c) =>
        untilView(tester, c, (v) => v.passengers.any((p) => p.nearStopPulse)),
  ),
];

/// The US4 states: each event's look, and the dispute card.
List<TripCase> us4TripCases() => [
  TripCase(
    'bump',
    fixture: 'event__bump_collect_and_lose',
    prepare: (tester, c) => untilView(tester, c, (v) => v.dropped.isNotEmpty),
  ),
  TripCase(
    'traffic',
    fixture: 'event__traffic',
    prepare: (tester, c) =>
        untilView(tester, c, (v) => v.windows.road == Road.traffic),
  ),
  TripCase(
    'open_road',
    fixture: 'event__open_road_clamped',
    prepare: (tester, c) =>
        untilView(tester, c, (v) => v.windows.road == Road.open),
  ),
  TripCase(
    'fast_forward',
    fixture: 'event__skipped',
    prepare: (tester, c) async {
      await untilView(tester, c, (v) => v.fastForward);
      // The strip faded in.
      await tester.pump(const Duration(milliseconds: 300));
    },
  ),
  TripCase(
    'fare_banner',
    fixture: 'event__fare_increase',
    prepare: (tester, c) async {
      await untilView(tester, c, (v) => v.banner != null);
      // Down and holding, the new price in place.
      advanceMs(c, 330);
      await tester.pump(const Duration(milliseconds: 300));
    },
  ),
  TripCase(
    'drop_me_here',
    fixture: 'event__drop_me_here',
    prepare: (tester, c) =>
        untilView(tester, c, (v) => v.passengers.any((p) => p.dropMeHere)),
  ),
  TripCase(
    'change_request',
    fixture: 'event__change_request',
    prepare: (tester, c) => untilView(
      tester,
      c,
      (v) => v.choices.whereType<ChangeRequestChoice>().isNotEmpty,
    ),
  ),
  TripCase(
    'dispute',
    fixture: 'event__payment_dispute',
    prepare: (tester, c) async {
      await untilView(tester, c, (v) => v.phase == TripPhase.disputeOpen);
      await tester.pump(const Duration(milliseconds: 300));
    },
  ),
  TripCase(
    'roadside_pickup',
    fixture: 'event__roadside_pickup',
    prepare: (tester, c) async {
      await untilView(
        tester,
        c,
        (v) => v.passengers.any((p) => p.presence == PresenceView.boarding),
      );
      // Halfway through the door, waving.
      advanceMs(c, 297);
      await tester.pump();
    },
  ),
];

/// A new player's economy holding [stock] and [bonat].
Future<TestEconomy> stockedEconomy({
  Map<BoosterId, int> stock = const {},
  int bonat = 0,
}) => testEconomy(
  firstState: (nowMs) => EconomyState.newPlayer(
    fuelMax: 5,
    nowMs: nowMs,
  ).copyWith(inventory: stock, bonat: bonat),
);

/// The US5 states: the boosters row with and without stock, the purchase
/// card (affordable, then short), break mode, the ledger's badges, and a
/// first-time hint.
List<TripCase> us5TripCases() => [
  TripCase(
    'boosters',
    economy: () => stockedEconomy(
      stock: {BoosterId.changeBag: 2, BoosterId.ledgerPeek: 1},
    ),
    prepare: (tester, c) async {
      advanceMs(c, 1000);
      await tester.pump();
    },
  ),
  TripCase(
    'booster_card',
    economy: () => stockedEconomy(bonat: 50),
    prepare: (tester, c) async {
      advanceMs(c, 1000);
      await c.useBooster(BoosterId.changeBag);
      await tester.pumpAndSettle();
    },
  ),
  TripCase(
    'booster_card_short',
    economy: () => stockedEconomy(bonat: 3),
    prepare: (tester, c) async {
      advanceMs(c, 1000);
      await c.useBooster(BoosterId.changeBag);
      unawaited(c.buyBooster());
      await tester.pumpAndSettle();
      expect(c.model.boosterCard?.shortBy, isNotNull);
    },
  ),
  TripCase(
    'break_mode',
    tripId: 'line_gamaa.02',
    prepare: (tester, c) async {
      advanceMs(c, 1000);
      c.startBreak();
      await tester.pump();
    },
  ),
  TripCase(
    'ledger_peek',
    economy: () => stockedEconomy(stock: {BoosterId.ledgerPeek: 1}),
    prepare: (tester, c) async {
      advanceMs(c, 1000);
      unawaited(c.useBooster(BoosterId.ledgerPeek));
      await tester.pumpAndSettle();
      expect(c.view!.passengers.any((p) => p.ledgerBadge != null), isTrue);
    },
  ),
  const TripCase('hint', fixture: 'sample__line_gamaa_01_three_stars'),
];

/// The US6 states: the failure card with the revive (affordable, then
/// short) and without it, and a story trip's condition.
List<TripCase> us6TripCases() {
  final price = sampleContent().price(SkuKind.revive, 'revive')!.amount;
  Future<void> fail(WidgetTester tester, TripController c) async {
    while (c.phase == TripPhase.running) {
      c.advance(const Duration(milliseconds: engineStepMs));
    }
    await tester.pumpAndSettle();
  }

  return [
    TripCase(
      'failed',
      fixture: 'ending__failed',
      economy: () => stockedEconomy(bonat: price),
      prepare: fail,
    ),
    TripCase('failed_short', fixture: 'ending__failed', prepare: fail),
    TripCase(
      'failed_story',
      fixture: 'ending__story_fight_fails',
      economy: () => stockedEconomy(bonat: price),
      prepare: fail,
    ),
    TripCase(
      'story',
      fixture: 'ending__story_fight_fails',
      prepare: (tester, c) async {
        advanceMs(c, 3000);
        await tester.pump();
      },
    ),
  ];
}

Future<void> _pauseAfter(WidgetTester tester, TripController c) async {
  advanceMs(c, 4000);
  c.pause(PauseReason.button);
  await tester.pumpAndSettle();
}

/// Opens [state] on [surface].
Future<void> openTripCase(
  WidgetTester tester,
  TripCase state, {
  TripSurface surface = TripSurface.reference,
  DigitStyle digits = DigitStyle.arabicIndic,
  double textScale = 1.0,
}) async {
  final economy = switch (state.economy) {
    final make? => await make(),
    null when state.emptyTank || state.lastLiter => await testEconomy(
      firstState: (nowMs) =>
          EconomyState.newPlayer(fuelMax: 5, nowMs: nowMs).copyWith(
            fuel: FuelState(
              liters: state.lastLiter ? 1 : 0,
              countedFromMs: nowMs,
            ),
          ),
    ),
    null => null,
  };
  final fixture = switch (state.fixture) {
    final name? => loadFixture(name),
    null => null,
  };
  await pumpTrip(
    tester,
    tripId: fixture?.definition.tripId ?? state.tripId,
    fixed: fixture == null
        ? null
        : FixedTrip(
            definition: fixture.definition,
            params: fixture.params,
            seed: fixture.seed,
          ),
    surface: surface,
    digits: digits,
    textScale: textScale,
    economy: economy,
    settle: !state.emptyTank,
  );
  await state.prepare?.call(tester, controllerOf(tester));
}

/// What the app puts on the clipboard, as the platform receives it.
List<String> clipboardOf(WidgetTester tester) {
  final copied = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add(
          (call.arguments as Map<Object?, Object?>)['text']! as String,
        );
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return copied;
}
