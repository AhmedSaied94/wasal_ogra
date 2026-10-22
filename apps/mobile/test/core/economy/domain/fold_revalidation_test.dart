import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/economy/domain/economy_state.dart';
import 'package:wassal/core/economy/domain/fold.dart';
import 'package:wassal/core/economy/domain/op.dart';
import 'package:wassal/core/economy/domain/rules.dart';
import 'package:wassal/core/economy/domain/txn_id.dart';

import '../../../helpers/economy.dart';

// What a rejection takes with it (research R6): the fold re-checks every
// op still in play, leaves out the ones that no longer apply, and is
// lenient where the device can't know better.

const _rules = ProductionRules();
const _minuteMs = 60000;

/// Requests applied in order on [base], each a minute after the last.
final class _Log {
  _Log(this.base) : state = base;

  final EconomyState base;
  EconomyState state;
  final ops = <Op>[];
  var _n = 0;

  Op send(OpRequest request) {
    _n++;
    final op = validatedOp(
      _rules.validate(
        state,
        request,
        ruleContext(nowMs: testEpochMs + _n * _minuteMs, id: _n),
      ),
    );
    state = _rules.apply(state, op);
    ops.add(op);
    return op;
  }

  /// The fold without [rejected].
  FoldResult without(Op rejected) => fold(base, [
    for (final op in ops)
      if (op.txnId != rejected.txnId) op,
  ], _rules);
}

EconomyState _player({int jenehat = 0, int bonat = 0, int liters = 5}) =>
    EconomyState(
      jenehat: jenehat,
      bonat: bonat,
      fuel: FuelState(liters: liters, countedFromMs: testEpochMs),
    );

Op _start(_Log log, [String tripId = 'line_hay.01']) =>
    log.send(StartTripRequest(tripId));

Op _result(_Log log, Op start, {int earnings = 15, bool revived = false}) =>
    log.send(
      RecordResultRequest(
        start: start.txnId,
        result: tripResult(
          tripId: start.string('trip_id'),
          earnings: earnings,
          revived: revived,
        ),
      ),
    );

List<TxnId> _ids(Iterable<Op> ops) => [for (final op in ops) op.txnId];

void main() {
  test('a rejected booster purchase leaves out the later use', () {
    final log = _Log(_player(bonat: 10));
    final buy = log.send(
      const BuyRequest(kind: SkuKind.booster, skuId: 'change_bag'),
    );
    _start(log);
    final use = log.send(const UseBoosterRequest(BoosterId.changeBag));

    final folded = log.without(buy);
    expect(folded.leftOut, [use.txnId]);
    expect(folded.state.bonat, 10);
    expect(folded.state.inventory, isEmpty);
    expect(folded.state.unfinished, isNotNull);
  });

  test('a rejected trip start leaves out its result and its ×2', () {
    final log = _Log(_player());
    final start = _start(log);
    final result = _result(log, start);
    final doubled = log.send(const AdRewardRequest(AdPlacement.resultDouble));

    final folded = log.without(start);
    expect(folded.leftOut, _ids([result, doubled]));
    expect(folded.state.jenehat, 0);
    expect(folded.state.progress, isEmpty);
    expect(folded.state.lastResult, isNull);
    expect(folded.state.fuel.liters, 5);
  });

  test('a rejected paid result leaves out a purchase that needed it', () {
    final log = _Log(_player(jenehat: 140));
    final start = _start(log);
    final result = _result(log, start, earnings: 20);
    final buy = log.send(
      const BuyRequest(
        kind: SkuKind.item,
        skuId: 'salon.sitara',
        variantId: 'plain',
      ),
    );

    final folded = log.without(result);
    expect(folded.leftOut, [buy.txnId]);
    expect(folded.state.jenehat, 140);
    expect(folded.state.ownership, isEmpty);
    // Its trip is still running: the start wasn't rejected.
    expect(folded.state.unfinished?.startTxn, start.txnId);
  });

  test('a rejected ×2 leaves the rest', () {
    final log = _Log(_player(jenehat: 140));
    final start = _start(log);
    _result(log, start, earnings: 15);
    final doubled = log.send(const AdRewardRequest(AdPlacement.resultDouble));
    log.send(
      const BuyRequest(
        kind: SkuKind.item,
        skuId: 'salon.sitara',
        variantId: 'plain',
      ),
    );

    final folded = log.without(doubled);
    expect(folded.leftOut, isEmpty);
    expect(folded.state.jenehat, 140 + 15 - 150);
    expect(folded.state.lastResult?.doubled, isFalse);
    expect(folded.state.ownership.keys, [(SkuKind.item, 'salon.sitara')]);
  });

  test('a rejected revive purchase leaves the trip', () {
    final log = _Log(_player(bonat: 20));
    final start = _start(log);
    final revive = log.send(
      const BuyRequest(kind: SkuKind.revive, skuId: 'revive'),
    );
    _result(log, start, revived: true);

    final folded = log.without(revive);
    expect(folded.leftOut, isEmpty);
    expect(folded.state.bonat, 20);
    expect(folded.state.unfinished, isNull);
    expect(folded.state.lastResult?.startTxn, start.txnId);
    expect(folded.state.jenehat, 15);
  });

  group('lenient', () {
    test('after a rejected refill, a start on an empty tank stays at 0', () {
      final log = _Log(_player(liters: 0));
      final refill = log.send(const AdRewardRequest(AdPlacement.fuelRefill));
      final start = _start(log);

      final folded = log.without(refill);
      expect(folded.leftOut, isEmpty);
      expect(folded.state.fuel.liters, 0);
      expect(folded.state.unfinished?.startTxn, start.txnId);
    });

    test('a rewarded refill the fold finds on a full tank adds nothing', () {
      final log = _Log(_player());
      final start = _start(log);
      log.send(const AdRewardRequest(AdPlacement.fuelRefill));

      final folded = log.without(start);
      expect(folded.leftOut, isEmpty);
      expect(folded.state.fuel.liters, 5);
      expect(folded.state.unfinished, isNull);
    });

    test('a bought refill after a rejected start still charges, full', () {
      final log = _Log(_player(bonat: 30));
      final start = _start(log);
      final refill = log.send(
        const BuyRequest(kind: SkuKind.fuel, skuId: 'refuel_full'),
      );

      final folded = log.without(start);
      expect(folded.leftOut, isEmpty);
      expect(folded.state.fuel.liters, 5);
      expect(folded.state.bonat, 30 + refill.bonatDelta);
    });
  });
}
