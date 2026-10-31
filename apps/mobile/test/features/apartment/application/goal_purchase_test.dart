// Buying the chapter's goal (specs/015-m10-apartment-story, contracts/
// apartment.md "GoalPurchase", T038): rules first, one request per intent,
// against a fake economy for every outcome, then the real one.
import 'dart:async';

import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/economy/economy.dart' hide Owned;
import 'package:wassal/core/progress/domain/unlocks.dart';
import 'package:wassal/features/apartment/application/goal_purchase.dart';

import '../../../helpers/economy.dart';
import '../../../helpers/progress.dart';

/// An economy that answers `buy` from [outcomes], in turn, and records each
/// call's id.
final class _FakeEconomy implements Economy {
  _FakeEconomy(this.outcomes);

  final List<FutureOr<OpOutcome>> outcomes;
  final calls = <(TxnId, SkuKind, String)>[];
  var _next = 100;

  @override
  TxnId newRequestId() => txnIdOf(_next++);

  @override
  Future<OpOutcome> buy(
    TxnId id, {
    required SkuKind kind,
    required String skuId,
    String? variantId,
  }) async {
    calls.add((id, kind, skuId));
    return outcomes.removeAt(0);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

OpApplied _applied() => OpApplied(op: _anyOp, view: _anyView, repeated: false);

late final LedgerOp _anyOp;
late final EconomyView _anyView;

void main() {
  late TestEconomy real;

  setUpAll(() async {
    final e = await testEconomy(
      firstState: (nowMs) => EconomyState.newPlayer(
        fuelMax: 5,
        nowMs: nowMs,
      ).copyWith(jenehat: 900),
    );
    final outcome = await e.service.buy(
      e.service.newRequestId(),
      kind: SkuKind.chapter,
      skuId: 'ch3_shabka',
    ) as OpApplied;
    _anyOp = outcome.op;
    _anyView = outcome.view;
    await e.db.close();
  });

  group('the rules come first', () {
    test('a locked chapter sends nothing', () async {
      final content = sampleWith((_) {});
      final economy = _FakeEconomy([]);
      final purchase = GoalPurchase(economy);
      final result = await purchase.buy(
        content,
        player(), // nothing met: chapter 3 is locked
        content.chapter(ChapterId.ch3Shabka)!,
      );
      expect(result, isA<GoalNotAllowed>());
      expect(economy.calls, isEmpty);
    });

    test('a non-purchase goal sends nothing', () async {
      final content = sampleWith((_) {});
      final economy = _FakeEconomy([]);
      final purchase = GoalPurchase(economy);
      final result = await purchase.buy(
        content,
        player(),
        content.chapter(ChapterId.ch1FirstJob)!,
      );
      expect(result, isA<GoalNotAllowed>());
      expect(economy.calls, isEmpty);
    });

    test('an owned chapter sends nothing', () async {
      final content = sampleWith((_) {});
      final economy = _FakeEconomy([]);
      final purchase = GoalPurchase(economy);
      final result = await purchase.buy(
        content,
        player(hayDone, {microOld, shabka}),
        content.chapter(ChapterId.ch3Shabka)!,
      );
      expect(result, isA<GoalNotAllowed>());
      expect(economy.calls, isEmpty);
    });
  });

  group('against a fake economy', () {
    test('applied buys once and clears the id', () async {
      final content = sampleWith((_) {});
      final economy = _FakeEconomy([_applied(), _applied()]);
      final purchase = GoalPurchase(economy);
      final chapter = content.chapter(ChapterId.ch3Shabka)!;
      expect(
        await purchase.buy(content, player(hayDone, {microOld}), chapter),
        isA<GoalBought>(),
      );
      expect(economy.calls.single, (
        txnIdOf(100),
        SkuKind.chapter,
        'ch3_shabka',
      ));
      await purchase.buy(content, player(hayDone, {microOld}), chapter);
      expect(economy.calls.last.$1, txnIdOf(101), reason: 'a new intent');
    });

    test('a double tap makes one buy (SC-002)', () async {
      final content = sampleWith((_) {});
      final gate = Completer<OpOutcome>();
      final economy = _FakeEconomy([gate.future]);
      final purchase = GoalPurchase(economy);
      final chapter = content.chapter(ChapterId.ch3Shabka)!;
      final first = purchase.buy(content, player(hayDone, {microOld}), chapter);
      expect(purchase.busy, isTrue);
      expect(
        await purchase.buy(content, player(hayDone, {microOld}), chapter),
        isA<GoalNotAllowed>(),
      );
      gate.complete(_applied());
      expect(await first, isA<GoalBought>());
      expect(economy.calls, hasLength(1));
      expect(purchase.busy, isFalse);
    });

    test('a retry after a failed write reuses the id', () async {
      final content = sampleWith((_) {});
      final economy = _FakeEconomy([const OpWriteFailed(), _applied()]);
      final purchase = GoalPurchase(economy);
      final chapter = content.chapter(ChapterId.ch3Shabka)!;
      expect(
        await purchase.buy(content, player(hayDone, {microOld}), chapter),
        isA<GoalWriteFailed>(),
      );
      expect(
        await purchase.buy(content, player(hayDone, {microOld}), chapter),
        isA<GoalBought>(),
      );
      expect(economy.calls[0].$1, economy.calls[1].$1);
    });

    test('short of money keeps the id; a final refusal clears it', () async {
      final content = sampleWith((_) {});
      for (final (code, kept) in [
        (EconomyRefusal.insufficientFunds, true),
        (EconomyRefusal.alreadyOwned, false),
        (EconomyRefusal.unknownSku, false),
      ]) {
        final economy = _FakeEconomy([OpRefused(code), _applied()]);
        final purchase = GoalPurchase(economy);
        final chapter = content.chapter(ChapterId.ch3Shabka)!;
        final refused = await purchase.buy(
          content,
          player(hayDone, {microOld}),
          chapter,
        );
        expect(refused, isA<GoalRefused>(), reason: code.name);
        expect((refused as GoalRefused).code, code);
        await purchase.buy(content, player(hayDone, {microOld}), chapter);
        expect(
          economy.calls[0].$1 == economy.calls[1].$1,
          kept,
          reason: code.name,
        );
      }
    });
  });

  test('the real economy buys the shabka once and spends its price', () async {
    real = await testEconomy(
      content: sampleWith((_) {}),
      firstState: (nowMs) => EconomyState.newPlayer(
        fuelMax: 5,
        nowMs: nowMs,
      ).copyWith(jenehat: 900),
    );
    addTearDown(real.close);
    final content = real.content;
    final purchase = GoalPurchase(real.service);
    final progress = player(hayDone, {microOld});

    expect(
      await purchase.buy(
        content,
        progress,
        content.chapter(ChapterId.ch3Shabka)!,
      ),
      isA<GoalBought>(),
    );
    expect(real.service.view.jenehat, 0);
    expect(real.service.view.owns(SkuKind.chapter, 'ch3_shabka'), isTrue);

    // A second tap is refused by the rules, and spends nothing.
    expect(
      await purchase.buy(
        content,
        player(hayDone, {microOld, shabka}),
        content.chapter(ChapterId.ch3Shabka)!,
      ),
      isA<GoalNotAllowed>(),
    );
    expect(real.service.view.jenehat, 0);
    // The chapter is met, so the story's current chapter moved on.
    expect(
      currentChapter(content, player(hayDone, {microOld, shabka}))!.chapterId,
      ChapterId.ch4Salon,
    );
  });
}
