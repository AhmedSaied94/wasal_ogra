import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/economy/economy.dart';

import '../../helpers/economy.dart';

// One charge per intent (SC-004, FR-016): the same id, sent again and again.

const _sends = 100;

Future<int> _rows(TestEconomy e) async =>
    (await dumpTables(e.db))['ledger_ops']!.length;

EconomyState Function(int) _with({int jenehat = 0, int bonat = 0}) =>
    (nowMs) => EconomyState.newPlayer(
      fuelMax: 5,
      nowMs: nowMs,
    ).copyWith(jenehat: jenehat, bonat: bonat);

void _expectRepeats(List<OpOutcome> outcomes, OpApplied first) {
  for (final outcome in outcomes) {
    expect(outcome, isA<OpApplied>());
    final applied = outcome as OpApplied;
    expect(applied.repeated, isTrue);
    expect(applied.op.seq, first.op.seq);
    expect(applied.op.op.txnId, first.op.op.txnId);
    expect(applied.op.op.bonatDelta, first.op.op.bonatDelta);
  }
}

void main() {
  test('100 sends in sequence: one row, one charge', () async {
    final e = await testEconomy(firstState: _with(bonat: 50));
    final id = e.service.newRequestId();
    Future<OpOutcome> buy() =>
        e.service.buy(id, kind: SkuKind.booster, skuId: 'change_bag');

    final first = await buy() as OpApplied;
    expect(first.repeated, isFalse);
    final rest = [for (var i = 1; i < _sends; i++) await buy()];

    _expectRepeats(rest, first);
    expect(await _rows(e), 1);
    expect(e.service.view.bonat, 40);
    expect(e.service.view.inventory[BoosterId.changeBag], 1);
  });

  test('100 sends at once: one row, one charge', () async {
    final e = await testEconomy(firstState: _with(jenehat: 500));
    final id = e.service.newRequestId();
    final outcomes = await Future.wait([
      for (var i = 0; i < _sends; i++)
        e.service.buy(
          id,
          kind: SkuKind.item,
          skuId: 'salon.nish',
          variantId: 'classic',
        ),
    ]);

    final first = outcomes.first as OpApplied;
    expect(first.repeated, isFalse);
    _expectRepeats(outcomes.skip(1).toList(), first);
    expect(await _rows(e), 1);
    expect(e.service.view.jenehat, 100);
    expect(e.service.view.variantOf('salon.nish'), 'classic');
  });

  test('a refused request retried with its id after earning applies', () async {
    final e = await testEconomy(firstState: _with(jenehat: 100));
    final id = e.service.newRequestId();
    Future<OpOutcome> buy() => e.service.buy(
      id,
      kind: SkuKind.item,
      skuId: 'salon.sitara',
      variantId: 'plain',
    );

    final refused = await buy();
    expect((refused as OpRefused).code, EconomyRefusal.insufficientFunds);
    expect(await _rows(e), 0);

    final start = e.service.newRequestId();
    await e.service.startTrip(start, tripId: 'line_gamaa.02');
    await e.service.recordResult(
      e.service.newRequestId(),
      start: start,
      result: tripResult(tripId: 'line_gamaa.02', earnings: 50),
    );
    expect(e.service.view.jenehat, 150);

    final applied = await buy() as OpApplied;
    expect(applied.repeated, isFalse);
    expect(e.service.view.jenehat, 0);
    expect(((await buy()) as OpApplied).repeated, isTrue);
    expect(e.service.view.jenehat, 0);
  });

  test('a repeat after a relaunch is still the stored op', () async {
    var e = await testEconomy(
      dbFile: tempDbFile(),
      firstState: _with(bonat: 30),
    );
    final id = e.service.newRequestId();
    final first = await e.service.buy(
      id,
      kind: SkuKind.booster,
      skuId: 'wake_all',
    ) as OpApplied;
    e = await reopen(e);
    final again = await e.service.buy(
      id,
      kind: SkuKind.booster,
      skuId: 'wake_all',
    ) as OpApplied;
    expect(again.repeated, isTrue);
    expect(again.op.seq, first.op.seq);
    expect(e.service.view.bonat, 22);
  });
}
