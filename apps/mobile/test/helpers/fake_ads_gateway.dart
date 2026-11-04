// A scripted `AdsGateway` (specs/018-m11-ads, contracts/ads-gateway.md,
// T025): outcomes and readiness per unit, consent, and a log of every call.
// With a `TripRunningProbe`, any call while the probe reads true fails the
// test (constitution IX, research R7, FR-009).
import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/ads/ads_gateway.dart';

/// One gateway call, as logged.
typedef AdCall = ({String method, AdUnit? unit, Object? arg});

final class FakeAdsGateway implements AdsGateway, AdsDebugControls {
  FakeAdsGateway({
    this.canRequestAds = true,
    this.formShown = false,
    Set<AdUnit> ready = const {},
    this.loadsBecomeReady = true,
  }) {
    for (final unit in AdUnit.values) {
      _readiness[unit] = ValueNotifier(
        ready.contains(unit) ? Readiness.ready : Readiness.notLoaded,
      );
    }
  }

  /// What consent answers.
  bool canRequestAds;

  /// Whether `start` showed the consent form (for the debug panel's tests).
  @override
  bool formShown;

  @override
  ConsentGeography geography = ConsentGeography.none;

  /// How many times the debug panel reset consent.
  int consentResets = 0;

  @override
  Future<void> resetConsent() async => consentResets++;

  /// Whether a `load` makes the unit ready at once. Off, it stays loading
  /// until [setReadiness].
  bool loadsBecomeReady;

  final calls = <AdCall>[];
  final _outcomes = <AdUnit, Queue<FutureOr<ShowOutcome>>>{};
  final _readiness = <AdUnit, ValueNotifier<Readiness>>{};
  TripRunningProbe? _probe;

  /// The configuration `start` was given.
  RequestConfig? startedWith;

  /// The verification each piggy show carried.
  final verifications = <PiggyVerification>[];

  /// Fails the test on any call while [probe] reads true.
  void failOnCallWhileRunning(TripRunningProbe probe) => _probe = probe;

  /// The next shows of [unit] come to [outcomes], in order; after them,
  /// [Rewarded].
  void script(AdUnit unit, List<FutureOr<ShowOutcome>> outcomes) =>
      (_outcomes[unit] ??= Queue()).addAll(outcomes);

  void setReadiness(AdUnit unit, Readiness readiness) =>
      _readiness[unit]!.value = readiness;

  List<String> get methods => [for (final c in calls) c.method];

  int count(String method, [AdUnit? unit]) => calls
      .where((c) => c.method == method && (unit == null || c.unit == unit))
      .length;

  void _log(String method, [AdUnit? unit, Object? arg]) {
    final probe = _probe;
    if (probe != null && probe.value) {
      throw TestFailure(
        'Ad SDK call "$method${unit == null ? '' : ' $unit'}" while a trip '
        'runs (constitution IX).',
      );
    }
    calls.add((method: method, unit: unit, arg: arg));
  }

  @override
  Future<bool> start(RequestConfig config) async {
    _log('start', null, config);
    startedWith = config;
    return canRequestAds;
  }

  @override
  Future<void> load(AdUnit unit) async {
    _log('load', unit);
    final readiness = _readiness[unit]!;
    if (readiness.value == Readiness.ready) return;
    readiness.value = loadsBecomeReady ? Readiness.ready : Readiness.loading;
  }

  @override
  ValueListenable<Readiness> readiness(AdUnit unit) => _readiness[unit]!;

  @override
  Future<ShowOutcome> show(
    AdUnit unit, {
    PiggyVerification? verification,
  }) async {
    _log('show', unit, verification);
    if (verification != null) verifications.add(verification);
    final readiness = _readiness[unit]!;
    if (readiness.value != Readiness.ready) return const ShowFailed();
    // A shown ad is spent.
    readiness.value = Readiness.notLoaded;
    final queue = _outcomes[unit];
    if (queue == null || queue.isEmpty) return const Rewarded();
    return queue.removeFirst();
  }
}
