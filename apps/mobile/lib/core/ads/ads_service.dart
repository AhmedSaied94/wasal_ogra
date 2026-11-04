// Offers, caps, pacing and rewards over the gateway and the economy
// (specs/018-m11-ads, contracts/ads-gateway.md "AdsService"). It decides from
// what the phone already holds (research R9–R11, R15) and never calls the
// SDK while a trip runs (constitution IX, research R7).
import 'dart:async';

import 'package:content_models/content_models.dart' show BoosterId;
import 'package:flutter/foundation.dart';
import 'package:trip_engine/trip_engine.dart' show TripOutcome;
import 'package:wassal/core/ads/ads_gateway.dart';
import 'package:wassal/core/ads/domain/ad_offer.dart';
import 'package:wassal/core/ads/domain/ads_may_start.dart';
import 'package:wassal/core/ads/domain/interstitial_due.dart';
import 'package:wassal/core/config/config_source.dart';
import 'package:wassal/core/config/tunable.dart';
import 'package:wassal/core/economy/domain/game_day.dart';
import 'package:wassal/core/economy/economy.dart';
import 'package:wassal/core/preferences/settings_store.dart';
import 'package:wassal/core/sync/domain/wire/bootstrap.dart';

export 'package:wassal/core/ads/domain/ad_offer.dart';

/// The two pacing preferences (data-model.md "Device preferences"). Only
/// [AdsServiceImpl] writes them.
const lastInterstitialTripKey = 'pref.ads_last_interstitial_trip';
const lastRewardedTripKey = 'pref.ads_last_rewarded_trip';

/// What the service reads of the rest of the app, each time it decides.
abstract interface class AdsWorld {
  bool get online;
  Entitlements get entitlements;

  /// Whether every tutorial trip is finished, and how many are.
  bool get tutorialDone;
  int get tutorialFinished;

  /// [tripId]'s index in the tutorial, or null.
  int? tutorialIndexOf(String tripId);
  EconomyView get view;
  AdsBlock? get adsBlock;

  /// The cached bootstrap's game day, or null.
  String? get bootstrapGameDay;

  /// Trusted now.
  int nowMs();
  ConfigSource get tunables;
}

/// What `watch` came to.
sealed class RewardOutcome {
  const RewardOutcome();
}

final class RewardApplied extends RewardOutcome {
  const RewardApplied(this.applied);

  final OpApplied applied;
}

/// The ad paid, but the economy refused the reward (the tank filled while
/// the ad ran, say).
final class RewardRefused extends RewardOutcome {
  const RewardRefused(this.code);

  final EconomyRefusal code;
}

/// Closed early, failed to show, or not offered.
final class NoReward extends RewardOutcome {
  const NoReward();
}

/// For M15's analytics (research R18).
enum AdEventKind {
  offered,
  rewarded,
  interstitialShown,
  loadFailed,
  piggyGaveUp,
}

final class AdEvent {
  const AdEvent(this.kind, [this.placement]);

  final AdEventKind kind;
  final AdPlacement? placement;

  @override
  String toString() => 'AdEvent(${kind.name}, ${placement?.wire})';
}

abstract interface class AdsService {
  /// Consent and the SDK's start, once per launch, then the preloads
  /// (research R6, R16). Never while a trip runs; offline it passes at once.
  Future<void> ensureReady();

  /// Whether [ensureReady] has run this launch and consent allows requests.
  bool get canRequestAds;

  /// Whether Settings must offer the privacy options (T081). Never asks
  /// while a trip runs.
  Future<bool> privacyOptionsRequired();

  /// The privacy options form. False when it couldn't show, or a trip runs.
  /// The player's choice applies at once.
  Future<bool> showPrivacyOptions();

  /// What a button shows now. Synchronous; reads caches only, never the
  /// SDK. [tripId] is the result's trip, for `result_double`.
  AdOffer offer(AdPlacement placement, {String? tripId});

  /// After every change an [offer] may answer differently for.
  Stream<void> get offersChanged;

  /// Shows the rewarded ad and, when it pays, applies the reward through
  /// the economy. The piggy goes through `PiggyService`. One call at a time
  /// per placement: a second while one runs gets the first's result.
  Future<RewardOutcome> watch(AdPlacement placement, {String? tripId});

  /// Shows a rewarded ad without applying its reward: the trip controller
  /// puts its intent row and engine command around the economy's call
  /// (contracts/seams.md "TripAdOffers"). True when the reward was earned.
  /// [verification] is the piggy's.
  Future<bool> showRewarded(
    AdPlacement placement, {
    PiggyVerification? verification,
  });

  /// The between-trips checkpoint (M08): consent when ads may start, the
  /// preloads, and the interstitial when it is due (research R10).
  Future<void> betweenTrips();

  /// Loads what the next trip and its result may offer (research R16).
  void preloadForNextTrip();

  /// Loads [placement]'s unit when the moment allows it (Home's piggy).
  void preload(AdPlacement placement);

  /// The piggy was attempted today: its banner hides for the game day.
  void markPiggyAttempted();

  Stream<AdEvent> get events;
}

final class AdsServiceImpl implements AdsService {
  AdsServiceImpl({
    required this._gateway,
    required this._economy,
    required this._settings,
    required this._world,
    required this._probe,
  }) {
    for (final unit in AdUnit.values) {
      final readiness = _gateway.readiness(unit);
      void listener() {
        if (readiness.value == Readiness.failed) {
          _emit(AdEvent(AdEventKind.loadFailed, _placementOf(unit)));
        }
        _changed();
      }

      readiness.addListener(listener);
      _unlisten.add(() => readiness.removeListener(listener));
    }
  }

  final AdsGateway _gateway;
  final Economy _economy;
  final SettingsStore _settings;
  final AdsWorld _world;
  final TripRunningProbe _probe;
  final _unlisten = <VoidCallback>[];
  final _changes = StreamController<void>.broadcast();
  final _events = StreamController<AdEvent>.broadcast();

  bool _started = false;
  bool _canRequest = false;
  Future<void>? _starting;

  /// Refill ads on [_countedDay], read from the log (research R9).
  String? _countedDay;
  int _refillsToday = 0;
  String? _piggyAttemptedDay;
  final _offeredShown = <AdPlacement>{};
  final _inFlight = <AdPlacement, Future<RewardOutcome>>{};

  /// One request id per player intent, kept until the intent ends
  /// (M05 research R10).
  final _heldIds = <AdPlacement, TxnId>{};
  bool _disposed = false;

  @override
  bool get canRequestAds => _canRequest;

  @override
  Stream<void> get offersChanged => _changes.stream;

  @override
  Stream<AdEvent> get events => _events.stream;

  bool get _tripRuns => _probe.value;

  String get _today => gameDayOf(_world.nowMs());

  @override
  Future<void> ensureReady() async {
    if (_started || _tripRuns) return;
    if (!_world.online) {
      // Nothing loads offline; the next checkpoint online starts it.
      await _countRefills();
      return;
    }
    await (_starting ??= _start());
  }

  Future<void> _start() async {
    try {
      _canRequest = await _gateway.start(adRequestConfig());
      _started = true;
    } finally {
      _starting = null;
    }
    await _countRefills();
    preloadForNextTrip();
    _changed();
  }

  @override
  Future<bool> privacyOptionsRequired() async =>
      !_tripRuns && await _gateway.privacyOptionsRequired();

  @override
  Future<bool> showPrivacyOptions() async {
    if (_tripRuns || !await _gateway.showPrivacyOptions()) return false;
    final allowed = await _gateway.mayRequestAds();
    // Before the first start, the start reads the choice itself.
    if (!_started) return true;
    if (allowed && !_canRequest) {
      // The refused start never started the SDK: the next checkpoint does.
      _started = false;
    } else {
      _canRequest = allowed;
    }
    _changed();
    return true;
  }

  @override
  AdOffer offer(AdPlacement placement, {String? tripId}) {
    final answer = adOffer(placement, _facts(placement, tripId));
    if (answer is Offered) {
      if (_offeredShown.add(placement)) {
        _emit(AdEvent(AdEventKind.offered, placement));
      }
    } else {
      _offeredShown.remove(placement);
    }
    return answer;
  }

  AdFacts _facts(AdPlacement placement, String? tripId) {
    final view = _world.view;
    final unfinished = view.unfinished;
    final last = view.lastResult;
    final tunables = _world.tunables;
    final today = _today;
    if (_countedDay != today) {
      // A new game day: the count is 0 until the log is read again.
      unawaited(_countRefills());
    }
    final block = _world.adsBlock;
    return AdFacts(
      online: _world.online,
      loaded:
          _canRequest &&
          _gateway.readiness(AdUnit.of(placement)).value == Readiness.ready,
      tutorialDone: _world.tutorialDone,
      resultDoublable:
          last != null &&
          last.outcome == TripOutcome.finished &&
          last.earningsJenehat > 0 &&
          !last.doubled,
      resultTutorialIndex: tripId == null
          ? null
          : _world.tutorialIndexOf(tripId),
      revivable: unfinished != null,
      revived: unfinished?.revived ?? false,
      trafficJamStock: view.inventory[BoosterId.trafficJam] ?? 0,
      trafficJamAds: unfinished?.trafficJamAds ?? 0,
      tankFull:
          view.fuel.liters >= view.fuel.max ||
          view.fuel.unlimitedUntilMs != null,
      refillsToday: _countedDay == today ? _refillsToday : 0,
      refillCap: tunables.read(Tunable.adsFuelRefillDailyCap),
      piggyBannerShows:
          block != null &&
          block.piggyAvailable &&
          _world.bootstrapGameDay == today &&
          _piggyAttemptedDay != today,
    );
  }

  Future<void> _countRefills() async {
    final day = _today;
    final count = await _economy.adRewardsOn(AdPlacement.fuelRefill, day);
    if (_disposed) return;
    final changed = _countedDay != day || _refillsToday != count;
    _countedDay = day;
    _refillsToday = count;
    if (changed) _changed();
  }

  @override
  Future<RewardOutcome> watch(AdPlacement placement, {String? tripId}) {
    assert(
      placement != AdPlacement.morningPiggy,
      'The piggy goes through PiggyService (constitution IV).',
    );
    return _inFlight[placement] ??=
        _watch(
          placement,
          tripId,
          // A block body: `remove` returns this very future, which whenComplete
          // would wait for, and it would never complete.
        ).whenComplete(() {
          _inFlight.remove(placement);
        });
  }

  Future<RewardOutcome> _watch(AdPlacement placement, String? tripId) async {
    if (placement == AdPlacement.fuelRefill) await _countRefills();
    if (offer(placement, tripId: tripId) is! Offered) return const NoReward();
    final id = _heldIds[placement] ??= _economy.newRequestId();
    if (!await showRewarded(placement)) {
      _heldIds.remove(placement);
      return const NoReward();
    }
    if (placement == AdPlacement.fuelRefill) {
      // Checked again: another refill may have landed while the ad ran.
      await _countRefills();
      final cap = _world.tunables.read(Tunable.adsFuelRefillDailyCap);
      if (_refillsToday >= cap) {
        _heldIds.remove(placement);
        return const RewardRefused(EconomyRefusal.capReached);
      }
    }
    var outcome = await _economy.applyAdReward(id, placement: placement);
    // A full disk: once more with the same id, then give up (research R11).
    if (outcome is OpWriteFailed) {
      outcome = await _economy.applyAdReward(id, placement: placement);
    }
    _heldIds.remove(placement);
    if (placement == AdPlacement.fuelRefill) await _countRefills();
    _changed();
    return switch (outcome) {
      OpApplied() => RewardApplied(outcome),
      OpRefused(:final code) => RewardRefused(code),
      OpWriteFailed() => const NoReward(),
    };
  }

  @override
  Future<bool> showRewarded(
    AdPlacement placement, {
    PiggyVerification? verification,
  }) async {
    if (_tripRuns || !_canRequest) return false;
    final unit = AdUnit.of(placement);
    final shown = await _gateway.show(unit, verification: verification);
    final rewarded = shown is Rewarded;
    if (rewarded) {
      await _writeTrips(lastRewardedTripKey);
      _emit(AdEvent(AdEventKind.rewarded, placement));
    }
    // Reload while the moment still allows it (paused, or between trips).
    if (!_tripRuns) unawaited(_gateway.load(unit));
    _changed();
    return rewarded;
  }

  @override
  Future<void> betweenTrips() async {
    if (_tripRuns) return;
    if (adsMayStart(
      tutorialDone: _world.tutorialDone,
      tutorialFinished: _world.tutorialFinished,
    )) {
      await ensureReady();
      if (_started) preloadForNextTrip();
    }
    if (!_canRequest) return;
    final trips = await _economy.tripStarts();
    final entitlements = _world.entitlements;
    final tunables = _world.tunables;
    final due = interstitialDue(
      trips: trips,
      lastInterstitialAt: _readInt(lastInterstitialTripKey),
      lastRewardedAt: _readInt(lastRewardedTripKey),
      tutorialDone: _world.tutorialDone,
      removeAds: entitlements.removeAds,
      noInterstitials: entitlements.noInterstitials,
      online: _world.online,
      loaded: _gateway.readiness(AdUnit.interstitial).value == Readiness.ready,
      graceTrips: tunables.read(Tunable.adsInterstitialGraceTrips),
      everyNTrips: tunables.read(Tunable.adsInterstitialEveryNTrips),
    );
    // A trip may have started during the awaits above (constitution IX).
    if (!due || _tripRuns) return;
    final shown = await _gateway.show(AdUnit.interstitial);
    // A failed show writes nothing (FR-022).
    if (shown is ShowFailed) return;
    await _settings.writeString(lastInterstitialTripKey, '$trips');
    _emit(const AdEvent(AdEventKind.interstitialShown));
    unawaited(_gateway.load(AdUnit.interstitial));
  }

  @override
  void preloadForNextTrip() {
    if (_tripRuns || !_canRequest) return;
    final done = _world.tutorialDone;
    final entitlements = _world.entitlements;
    final units = <AdUnit>[
      AdUnit.resultDouble,
      // Before the tutorial is done only the ×2 may show (research R15).
      if (done) ...[
        AdUnit.tripRevive,
        AdUnit.trafficJam,
        AdUnit.fuelRefill,
        if (!entitlements.removeAds && !entitlements.noInterstitials)
          AdUnit.interstitial,
      ],
    ];
    for (final unit in units) {
      unawaited(_gateway.load(unit));
    }
  }

  @override
  void preload(AdPlacement placement) {
    if (_tripRuns || !_canRequest) return;
    unawaited(_gateway.load(AdUnit.of(placement)));
  }

  @override
  void markPiggyAttempted() {
    _piggyAttemptedDay = _today;
    _changed();
  }

  Future<void> _writeTrips(String key) async {
    final trips = await _economy.tripStarts();
    await _settings.writeString(key, '$trips');
  }

  int _readInt(String key) =>
      int.tryParse(_settings.readString(key) ?? '') ?? 0;

  AdPlacement? _placementOf(AdUnit unit) {
    for (final placement in AdPlacement.values) {
      if (AdUnit.of(placement) == unit) return placement;
    }
    return null;
  }

  void _changed() {
    if (!_disposed) _changes.add(null);
  }

  void _emit(AdEvent event) {
    if (!_disposed) _events.add(event);
  }

  void dispose() {
    _disposed = true;
    for (final unlisten in _unlisten) {
      unlisten();
    }
    unawaited(_changes.close());
    unawaited(_events.close());
  }
}
