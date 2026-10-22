import 'dart:math';

import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/economy/domain/economy_refusal.dart';
import 'package:wassal/core/economy/domain/economy_state.dart';
import 'package:wassal/core/economy/domain/fuel.dart';
import 'package:wassal/core/economy/domain/op.dart';
import 'package:wassal/core/economy/domain/rules.dart';
import 'package:wassal/core/economy/domain/trusted_time.dart';

import '../../helpers/economy.dart';

// A simulated week of play (SC-003): starts, rewarded refills, unlimited
// windows, clock changes and restarts, through the domain rules, against
// a reference that counts liters one second at a time.

const _seed = 20261022;
const _max = 5;
const _regenSeconds = 20 * 60;
const _week = 7 * 24 * 3600;
const _rules = ProductionRules();

/// Liters as a player would count them, second by second. It knows nothing
/// of `countedFrom`.
final class _Reference {
  int liters = _max;

  /// Seconds toward the next liter.
  int counted = 0;
  int? unlimitedUntilMs;

  void tick() {
    if (liters >= _max) {
      counted = 0;
      return;
    }
    counted++;
    if (counted == _regenSeconds) {
      liters++;
      counted = 0;
    }
  }

  bool unlimitedAt(int nowMs) {
    final until = unlimitedUntilMs;
    return until != null && nowMs < until;
  }

  int? nextLiterAtMs(int nowMs) =>
      liters >= _max ? null : nowMs + (_regenSeconds - counted) * 1000;

  int? fullAtMs(int nowMs) => switch (nextLiterAtMs(nowMs)) {
    final next? => next + (_max - liters - 1) * _regenSeconds * 1000,
    null => null,
  };
}

/// The phone: real time, its uptime counter, its boot and its clock.
final class _Phone {
  _Phone() {
    anchor = firstAnchor(snapshot, deviceMs);
  }

  int realMs = testEpochMs;
  int elapsedMs = testBootElapsedMs;
  int boot = 1;
  int clockOffsetMs = 0;
  late ClockAnchor anchor;

  int get deviceMs => realMs + clockOffsetMs;

  BootSnapshot get snapshot =>
      BootSnapshot(elapsedRealtimeMs: elapsedMs, bootCount: boot);

  int get trustedMs => trustedNow(anchor, elapsedMs);

  void second() {
    realMs += 1000;
    elapsedMs += 1000;
  }

  /// Off for [offSeconds], then on with the clock [offsetMs] from real.
  void restart(int offSeconds, int offsetMs) {
    final latest = anchor.withLatest(trustedMs);
    realMs += offSeconds * 1000;
    boot++;
    elapsedMs = 30000;
    clockOffsetMs = offsetMs;
    expect(isRestart(latest, snapshot), isTrue);
    anchor = reanchor(latest, snapshot, deviceMs);
  }
}

void main() {
  test('a week of fuel matches the reference every minute', () {
    final random = Random(_seed);
    final phone = _Phone();
    final reference = _Reference();
    var state = EconomyState.newPlayer(
      fuelMax: _max,
      nowMs: phone.trustedMs,
    ).copyWith(bonat: 1000000);
    var nextId = 1;
    final counts = <String, int>{};

    RuleContext ctx() =>
        ruleContext(nowMs: phone.trustedMs, id: nextId++, fuelMax: _max);

    FuelView view() => fuelView(
      state.fuel,
      phone.trustedMs,
      max: _max,
      regenMs: regenMsOf(20),
    );

    void check(String when) {
      final now = phone.trustedMs;
      final actual = view();
      expect(actual.liters, reference.liters, reason: when);
      expect(actual.nextLiterAtMs, reference.nextLiterAtMs(now), reason: when);
      expect(actual.fullAtMs, reference.fullAtMs(now), reason: when);
    }

    void apply(Decision decision) =>
        state = _rules.apply(state, validatedOp(decision));

    void start() {
      final now = phone.trustedMs;
      final decision = _rules.validate(
        state,
        const StartTripRequest('line_hay.01'),
        ctx(),
      );
      if (!reference.unlimitedAt(now) && reference.liters == 0) {
        expect(declinedCode(decision), EconomyRefusal.noFuel);
        counts.update('refused', (n) => n + 1, ifAbsent: () => 1);
        return;
      }
      final start = validatedOp(decision);
      state = _rules.apply(state, start);
      if (!reference.unlimitedAt(now)) reference.liters--;
      apply(
        _rules.validate(
          state,
          RecordResultRequest(
            start: start.txnId,
            result: tripResult(tripId: 'line_hay.01'),
          ),
          ctx(),
        ),
      );
      counts.update('starts', (n) => n + 1, ifAbsent: () => 1);
    }

    void refill() {
      final decision = _rules.validate(
        state,
        const AdRewardRequest(AdPlacement.fuelRefill),
        ctx(),
      );
      if (reference.liters >= _max) {
        expect(declinedCode(decision), EconomyRefusal.tankFull);
        return;
      }
      apply(decision);
      reference
        ..liters = _max
        ..counted = 0;
      counts.update('refills', (n) => n + 1, ifAbsent: () => 1);
    }

    void unlimited() {
      final now = phone.trustedMs;
      apply(
        _rules.validate(
          state,
          const BuyRequest(
            kind: SkuKind.fuelUnlimited,
            skuId: 'fuel_unlimited_1h',
          ),
          ctx(),
        ),
      );
      final until = reference.unlimitedUntilMs;
      reference.unlimitedUntilMs =
          (until != null && until > now ? until : now) + unlimitedWindowMs;
      counts.update('windows', (n) => n + 1, ifAbsent: () => 1);
    }

    void clockChange() {
      final before = (phone.trustedMs, view());
      phone.clockOffsetMs = (random.nextInt(13) - 6) * 3600000;
      expect((phone.trustedMs, view()), before, reason: 'phone stays on');
      counts.update('clock changes', (n) => n + 1, ifAbsent: () => 1);
    }

    void restart() {
      final before = phone.trustedMs;
      final offsets = [0, 0, 3 * 3600000, -3 * 3600000, 90000];
      phone.restart(
        60 + random.nextInt(3 * 3600),
        offsets[random.nextInt(offsets.length)],
      );
      final jump = phone.trustedMs - before;
      expect(jump % 1000, 0);
      expect(jump, greaterThanOrEqualTo(0));
      for (var s = 0; s < jump ~/ 1000; s++) {
        reference.tick();
      }
      counts.update('restarts', (n) => n + 1, ifAbsent: () => 1);
    }

    for (var second = 1; second <= _week; second++) {
      phone.second();
      reference.tick();
      switch (random.nextInt(6000)) {
        case < 10:
          start();
        case < 12:
          refill();
        case 12:
          unlimited();
        case 13:
          clockChange();
        case 14 when random.nextInt(4) == 0:
          restart();
      }
      if (second % 60 == 0) check('second $second');
    }

    // The week exercised every kind of event.
    for (final kind in [
      'starts',
      'refused',
      'refills',
      'windows',
      'clock changes',
      'restarts',
    ]) {
      expect(counts[kind], greaterThan(0), reason: kind);
    }
  });
}
