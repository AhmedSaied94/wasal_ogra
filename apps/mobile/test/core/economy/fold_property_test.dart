import 'dart:math';

import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trip_engine/trip_engine.dart' show TripOutcome;
import 'package:wassal/core/economy/domain/fold.dart';
import 'package:wassal/core/economy/domain/op.dart';
import 'package:wassal/core/economy/domain/rules.dart';
import 'package:wassal/core/economy/economy.dart';

import '../../helpers/economy.dart';

// The projection is the fold (SC-001, invariant 1): random requests, valid
// and not, with time passing between them. After every step the state
// equals the fold of the base and the stored ops, each balance is the base
// plus its deltas, and none is below 0, also as the server rejects ops and
// replaces the base (T057). A failure names its seed.

const _rules = ProductionRules();
const _seeds = 1000;
const _serviceSeeds = 25;
const _maxSteps = 200;
const _minuteMs = 60000;

const _trips = [
  'line_gamaa.01',
  'line_gamaa.02',
  'line_hay.01',
  'line_hay.02',
  'line_hay.03',
  'line_nope.01',
];

/// Valid and invalid purchases of the sample pack.
const _buys = <(SkuKind, String, String?)>[
  (SkuKind.item, 'salon.nish', 'classic'),
  (SkuKind.item, 'salon.nish', 'crystal'),
  (SkuKind.item, 'salon.nish', 'gold'),
  (SkuKind.item, 'salon.nish', null),
  (SkuKind.item, 'salon.sitara', 'plain'),
  (SkuKind.vehicle, 'micro_old', null),
  (SkuKind.vehicle, 'tuktuk', null),
  (SkuKind.chapter, 'ch3_shabka', null),
  (SkuKind.chapter, 'ch1', null),
  (SkuKind.booster, 'change_bag', null),
  (SkuKind.booster, 'wake_all', null),
  (SkuKind.booster, 'ledger_peek', null),
  (SkuKind.booster, 'traffic_jam', null),
  (SkuKind.booster, 'revive', null),
  (SkuKind.fuel, 'refuel_full', null),
  (SkuKind.fuelUnlimited, 'fuel_unlimited_1h', null),
  (SkuKind.revive, 'revive', null),
];

/// A random request against [s]: mostly ones that could apply, some not.
OpRequest _request(Random random, EconomyState s) {
  final unfinished = s.unfinished;
  switch (random.nextInt(10)) {
    case 0 || 1:
      return StartTripRequest(_trips[random.nextInt(_trips.length)]);
    case 2 || 3:
      final start = unfinished != null && random.nextInt(5) > 0
          ? unfinished.startTxn
          : txnIdOf(900000 + random.nextInt(5));
      final tripId = unfinished != null && random.nextInt(6) > 0
          ? unfinished.tripId
          : _trips[random.nextInt(_trips.length)];
      final outcome =
          TripOutcome.values[random.nextInt(TripOutcome.values.length)];
      final finished = outcome == TripOutcome.finished;
      return RecordResultRequest(
        start: start,
        result: tripResult(
          tripId: tripId,
          outcome: outcome,
          stars: finished ? random.nextInt(6) - 1 : random.nextInt(8) ~/ 7,
          earnings: finished ? random.nextInt(65) - 1 : random.nextInt(10) ~/ 9,
          durationMs: 30000 + random.nextInt(120000),
        ),
      );
    case 4 || 5 || 6:
      final (kind, skuId, variantId) = _buys[random.nextInt(_buys.length)];
      return BuyRequest(kind: kind, skuId: skuId, variantId: variantId);
    case 7:
      return UseBoosterRequest(
        BoosterId.values[random.nextInt(BoosterId.values.length)],
      );
    default:
      return AdRewardRequest(
        AdPlacement.values[random.nextInt(AdPlacement.values.length)],
      );
  }
}

EconomyState _base(Random random, int nowMs) => EconomyState.newPlayer(
  fuelMax: 5,
  nowMs: nowMs,
).copyWith(jenehat: random.nextInt(3000), bonat: random.nextInt(300));

/// Checks the invariants for [state] over [base] and the [ops] in play
/// (stored after the base and not rejected). With [anyRejected] false,
/// nothing may be left out.
void _checkInvariants(
  EconomyState state,
  EconomyState base,
  List<Op> ops,
  String where, {
  required bool anyRejected,
}) {
  final folded = fold(base, ops, _rules);
  if (!anyRejected) {
    expect(folded.leftOut, isEmpty, reason: '$where: nothing left out');
  }
  expect(state, folded.state, reason: '$where: state is the fold');
  final leftOut = folded.leftOut.toSet();
  var jenehat = base.jenehat;
  var bonat = base.bonat;
  for (final op in ops) {
    if (leftOut.contains(op.txnId)) continue;
    jenehat += op.jenehatDelta;
    bonat += op.bonatDelta;
  }
  expect(state.jenehat, jenehat, reason: '$where: JENEHAT is Σ deltas');
  expect(state.bonat, bonat, reason: '$where: BONAT is Σ deltas');
  expect(state.jenehat, greaterThanOrEqualTo(0), reason: where);
  expect(state.bonat, greaterThanOrEqualTo(0), reason: where);
  expect(state.fuel.liters, greaterThanOrEqualTo(0), reason: where);
  for (final count in state.inventory.values) {
    expect(count, greaterThan(0), reason: where);
  }
}

/// Runs [body] for [seed], naming the seed on a failure.
Future<void> _withSeed(int seed, Future<void> Function() body) async {
  try {
    await body();
  } on TestFailure catch (e) {
    fail('seed $seed: ${e.message}');
  }
}

/// What a step does besides a request (T057): a rejection from the server
/// (10%), or a new base at the current state (2%).
enum _Event { request, reject, rebase }

_Event _event(Random random) => switch (random.nextInt(100)) {
  < 10 => _Event.reject,
  < 12 => _Event.rebase,
  _ => _Event.request,
};

void main() {
  test(
    '$_seeds seeds through the rules: the state is always the fold',
    () async {
      var applied = 0;
      var rejections = 0;
      for (var seed = 1; seed <= _seeds; seed++) {
        await _withSeed(seed, () async {
          final random = Random(seed);
          var now = testEpochMs;
          var base = _base(random, now);
          var state = base;
          // The ops in play: after the base, not rejected.
          var ops = <Op>[];
          var anyRejected = false;
          final steps = 1 + random.nextInt(_maxSteps);
          for (var step = 0; step < steps; step++) {
            now += random.nextInt(91) * _minuteMs;
            switch (_event(random)) {
              case _Event.reject when ops.isNotEmpty:
                final rejected = ops[random.nextInt(ops.length)];
                ops = [
                  for (final op in ops)
                    if (op.txnId != rejected.txnId) op,
                ];
                state = fold(base, ops, _rules).state;
                anyRejected = true;
                rejections++;
              case _Event.rebase:
                base = state;
                ops = [];
                anyRejected = false;
              case _:
                final request = _request(random, state);
                final decision = _rules.validate(
                  state,
                  request,
                  ruleContext(nowMs: now, id: step + 1),
                );
                if (decision case Validated(:final op)) {
                  state = _rules.apply(state, op);
                  ops.add(op);
                  applied++;
                }
            }
            _checkInvariants(
              state,
              base,
              ops,
              'step $step',
              anyRejected: anyRejected,
            );
          }
        });
      }
      // The requests were valid, and rejected, often enough to mean
      // something.
      expect(applied, greaterThan(_seeds * 20));
      expect(rejections, greaterThan(_seeds));
    },
  );

  test(
    '$_serviceSeeds seeds through the service: memory, tables and fold agree',
    () async {
      for (var seed = 1; seed <= _serviceSeeds; seed++) {
        await _withSeed(seed, () async {
          final random = Random(seed);
          var base = _base(random, testEpochMs);
          final e = await testEconomy(firstState: (_) => base);
          // Every stored op with its seq, and the ids rejected.
          final stored = <(int, Op)>[];
          final rejected = <TxnId>{};
          var afterSeq = 0;
          final steps = 1 + random.nextInt(_maxSteps);
          for (var step = 0; step < steps; step++) {
            e.passTime(minute * random.nextInt(91));
            switch (_event(random)) {
              case _Event.reject:
                final pending = await e.service.pendingOps(limit: 1000);
                if (pending.isEmpty) break;
                final id = pending[random.nextInt(pending.length)].op.txnId;
                await e.service.markRejected({id: 'property'});
                rejected.add(id);
              case _Event.rebase:
                base = e.service.state;
                afterSeq = stored.isEmpty ? 0 : stored.last.$1;
                await e.service.replaceBase(base, afterSeq: afterSeq);
              case _Event.request:
                final request = _request(random, e.service.state);
                final id = random.nextInt(20) == 0 && stored.isNotEmpty
                    ? stored[random.nextInt(stored.length)].$2.txnId
                    : e.service.newRequestId();
                final outcome = await _send(e, id, request);
                if (outcome case OpApplied(:final op, repeated: false)) {
                  stored.add((op.seq, op.op));
                }
            }
            final inPlay = [
              for (final (seq, op) in stored)
                if (seq > afterSeq && !rejected.contains(op.txnId)) op,
            ];
            _checkInvariants(
              e.service.state,
              base,
              inPlay,
              'step $step',
              anyRejected: rejected.isNotEmpty,
            );
            final tables = await e.store.load();
            expect(tables.state, e.service.state, reason: 'step $step tables');
            expect(tables.base.afterSeq, afterSeq, reason: 'step $step base');
            await e.store.checkProjection(_rules);
          }
          final pending = await e.service.pendingOps(limit: 1000);
          expect(
            [for (final p in pending) p.op.txnId],
            [
              for (final (_, op) in stored)
                if (!rejected.contains(op.txnId)) op.txnId,
            ],
          );
          await e.close();
        });
      }
    },
  );
}

/// Sends [request] with [id]. A reused id is only sent again when it was
/// the same request, as a retry would be.
Future<OpOutcome?> _send(TestEconomy e, TxnId id, OpRequest request) async {
  final stored = await e.store.findOp(id);
  if (stored != null && !requestMatches(stored.op, request)) return null;
  return switch (request) {
    StartTripRequest(:final tripId) => e.service.startTrip(id, tripId: tripId),
    RecordResultRequest(:final start, :final result) => e.service.recordResult(
      id,
      start: start,
      result: result,
    ),
    BuyRequest(:final kind, :final skuId, :final variantId) => e.service.buy(
      id,
      kind: kind,
      skuId: skuId,
      variantId: variantId,
    ),
    UseBoosterRequest(:final booster) => e.service.useBooster(
      id,
      booster: booster,
    ),
    AdRewardRequest(:final placement) => e.service.applyAdReward(
      id,
      placement: placement,
    ),
  };
}
