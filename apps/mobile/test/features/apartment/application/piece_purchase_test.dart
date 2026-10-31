// Buying a piece (specs/015-m10-apartment-story, contracts/apartment.md "The
// piece sheet", T053): rules first, one held id, and only the purchase that
// completes a room or chapter says so.
import 'dart:async';

import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/economy/economy.dart';
import 'package:wassal/core/progress/application/player_progress_provider.dart';
import 'package:wassal/features/apartment/application/piece_purchase.dart';

import '../../../helpers/economy.dart';
import '../../../helpers/progress.dart';

final class _FakeEconomy implements Economy {
  _FakeEconomy(this.outcomes);

  final List<FutureOr<OpOutcome>> outcomes;
  final calls = <(TxnId, SkuKind, String, String?)>[];
  var _next = 200;

  @override
  TxnId newRequestId() => txnIdOf(_next++);

  @override
  Future<OpOutcome> buy(
    TxnId id, {
    required SkuKind kind,
    required String skuId,
    String? variantId,
  }) async {
    calls.add((id, kind, skuId, variantId));
    return outcomes.removeAt(0);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

late final LedgerOp _anyOp;
late final EconomyView _anyView;

OpApplied _applied() => OpApplied(op: _anyOp, view: _anyView, repeated: false);

void main() {
  final content = artboardSalonContent();
  final nish = content.item('salon.nish')!;
  final antreeh = content.item('salon.antreeh')!;

  setUpAll(() async {
    final e = await testEconomy(
      content: content,
      firstState: (nowMs) => EconomyState.newPlayer(
        fuelMax: 5,
        nowMs: nowMs,
      ).copyWith(jenehat: 10000),
    );
    final outcome = await e.service.buy(
      e.service.newRequestId(),
      kind: SkuKind.item,
      skuId: 'salon.nish',
      variantId: 'classic',
    ) as OpApplied;
    _anyOp = outcome.op;
    _anyView = outcome.view;
    await e.db.close();
  });

  test('the rules come first: a locked chapter or an owned piece sends '
      'nothing', () async {
    final economy = _FakeEconomy([]);
    final purchase = PiecePurchase(economy, content);
    expect(
      (await purchase.buy(nish, 'classic', before: player())).outcome,
      isNull,
    );
    expect(economy.calls, isEmpty);
    final owned = await purchase.buy(
      nish,
      'classic',
      before: player(hayDone, {microOld, shabka, (SkuKind.item, 'salon.nish')}),
    );
    expect(owned.outcome, isNull);
    expect(economy.calls, isEmpty);
  });

  test(
    'one held id: failures and a short balance keep it, applied clears it',
    () async {
      final before = player(hayDone, {microOld, shabka});
      final economy = _FakeEconomy([
        const OpWriteFailed(),
        const OpRefused(EconomyRefusal.insufficientFunds),
        _applied(),
        _applied(),
      ]);
      final purchase = PiecePurchase(economy, content);
      for (var i = 0; i < 3; i++) {
        await purchase.buy(nish, 'classic', before: before);
      }
      expect(economy.calls[0].$1, economy.calls[2].$1);
      await purchase.buy(nish, 'classic', before: before);
      expect(economy.calls[3].$1, isNot(economy.calls[2].$1));
      expect(economy.calls.first.$4, 'classic');
    },
  );

  test('a double tap makes one buy (SC-002)', () async {
    final gate = Completer<OpOutcome>();
    final economy = _FakeEconomy([gate.future]);
    final purchase = PiecePurchase(economy, content);
    final before = player(hayDone, {microOld, shabka});
    final first = purchase.buy(nish, 'classic', before: before);
    expect(purchase.busy, isTrue);
    final second = await purchase.buy(nish, 'classic', before: before);
    expect(second.outcome, isNull);
    gate.complete(_applied());
    await first;
    expect(economy.calls, hasLength(1));
  });

  test('the real economy: only the last piece completes the room and the '
      'chapter', () async {
    final all = [for (final item in content.itemsOf(RoomId.salon)) item.itemId];
    Future<PiecePurchaseResult> buyWith(int ownedCount, String itemId) async {
      final e = await testEconomy(
        content: content,
        firstState: (nowMs) =>
            EconomyState.newPlayer(fuelMax: 5, nowMs: nowMs).copyWith(
              jenehat: 10000,
              progress: {
                for (final id in hayDone.keys)
                  id: const TripProgress(bestStars: 1, plays: 1),
              },
              ownership: {
                (SkuKind.vehicle, 'micro_old'): Owned(
                  kind: SkuKind.vehicle,
                  acquiredAtMs: 0,
                ),
                (SkuKind.chapter, 'ch3_shabka'): Owned(
                  kind: SkuKind.chapter,
                  acquiredAtMs: 0,
                ),
                for (final id in all.take(ownedCount))
                  (SkuKind.item, id): Owned(
                    kind: SkuKind.item,
                    acquiredAtMs: 0,
                    variantId: 'classic',
                  ),
              },
            ),
      );
      addTearDown(e.close);
      final purchase = PiecePurchase(e.service, content);
      final before = playerProgressOf(e.service.view, content);
      return purchase.buy(content.item(itemId)!, 'classic', before: before);
    }

    final first = await buyWith(0, 'salon.nish');
    expect((first.roomCompleted, first.chapterCompleted), (false, false));

    final last = await buyWith(3, all.last);
    expect((last.roomCompleted, last.chapterCompleted), (true, true));
    expect(antreeh.roomId, RoomId.salon);
  });
}
