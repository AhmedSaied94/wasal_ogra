// Buying a vehicle (specs/014-m09-lines-vehicles, contracts/buy-vehicle.md
// "Buying", SC-004): one request per intent, against a fake economy for
// every outcome, then against the real one.
import 'dart:async';

import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/economy/economy.dart' hide Owned;
import 'package:wassal/core/progress/domain/playable.dart';
import 'package:wassal/core/progress/domain/player_progress.dart';
import 'package:wassal/features/lines/application/vehicle_purchase.dart';
import 'package:wassal/features/lines/domain/vehicle_offer.dart';

import '../../../helpers/economy.dart';

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

/// The sample's micro_old, for sale at 1,500 to a player with [jenehat].
VehicleOffer _offer({
  int jenehat = 2000,
  VehicleSale sale = const ForSale(1500),
}) => VehicleOffer(
  vehicle: VehicleId.microOld,
  name: 'x',
  starter: false,
  seats: 10,
  currentSeats: 3,
  opensLine: LineId.lineGamaa,
  sale: sale,
  jenehat: jenehat,
  impact: null,
);

OpApplied _applied() => OpApplied(op: _anyOp, view: _anyView, repeated: false);

late final LedgerOp _anyOp;
late final EconomyView _anyView;

void main() {
  late TestEconomy real;

  setUpAll(() async {
    // An applied outcome needs a real op and view; take them from a real
    // purchase.
    final e = await testEconomy(
      firstState: (nowMs) => EconomyState.newPlayer(
        fuelMax: 5,
        nowMs: nowMs,
      ).copyWith(jenehat: 2000),
    );
    final outcome = await e.service.buy(
      e.service.newRequestId(),
      kind: SkuKind.vehicle,
      skuId: 'micro_old',
    ) as OpApplied;
    _anyOp = outcome.op;
    _anyView = outcome.view;
    await e.db.close();
  });

  group('against a fake economy', () {
    test('applied buys once and clears the id', () async {
      final economy = _FakeEconomy([_applied(), _applied()]);
      final purchase = VehiclePurchase(economy);
      expect(await purchase.buy(_offer()), isA<OpApplied>());
      expect(economy.calls.single, (
        txnIdOf(100),
        SkuKind.vehicle,
        'micro_old',
      ));
      await purchase.buy(_offer());
      expect(economy.calls.last.$1, txnIdOf(101), reason: 'a new intent');
    });

    test('a double tap makes one buy', () async {
      final gate = Completer<OpOutcome>();
      final economy = _FakeEconomy([gate.future]);
      final purchase = VehiclePurchase(economy);
      final first = purchase.buy(_offer());
      expect(purchase.busy, isTrue);
      expect(await purchase.buy(_offer()), isNull);
      gate.complete(_applied());
      expect(await first, isA<OpApplied>());
      expect(economy.calls, hasLength(1));
      expect(purchase.busy, isFalse);
    });

    test('a retry after a failed write reuses the id', () async {
      final economy = _FakeEconomy([const OpWriteFailed(), _applied()]);
      final purchase = VehiclePurchase(economy);
      expect(await purchase.buy(_offer()), isA<OpWriteFailed>());
      expect(await purchase.buy(_offer()), isA<OpApplied>());
      expect(economy.calls[0].$1, economy.calls[1].$1);
    });

    test(
      'short of money keeps the id; owned or not for sale clear it',
      () async {
        for (final (code, kept) in [
          (EconomyRefusal.insufficientFunds, true),
          (EconomyRefusal.alreadyOwned, false),
          (EconomyRefusal.notForSale, false),
          (EconomyRefusal.unknownSku, false),
          (EconomyRefusal.catalogMismatch, false),
        ]) {
          final economy = _FakeEconomy([OpRefused(code), _applied()]);
          final purchase = VehiclePurchase(economy);
          expect(await purchase.buy(_offer()), _refused(code));
          await purchase.buy(_offer());
          expect(
            economy.calls[0].$1 == economy.calls[1].$1,
            kept,
            reason: code.wire,
          );
        }
      },
    );

    test('not for sale, or short, makes no call', () async {
      final economy = _FakeEconomy([]);
      final purchase = VehiclePurchase(economy);
      expect(await purchase.buy(_offer(sale: const Owned())), isNull);
      expect(
        await purchase.buy(_offer(sale: const NeedsFirst(VehicleId.tuktuk))),
        isNull,
      );
      expect(await purchase.buy(_offer(sale: const NoPrice())), isNull);
      expect(await purchase.buy(_offer(jenehat: 1499)), isNull);
      expect(economy.calls, isEmpty);
    });
  });

  group('against the real economy', () {
    setUp(() async {
      real = await testEconomy(
        firstState: (nowMs) => EconomyState.newPlayer(
          fuelMax: 5,
          nowMs: nowMs,
        ).copyWith(jenehat: 2000),
      );
    });

    tearDown(() => real.db.close());

    test('the price is spent once and the vehicle is owned', () async {
      final purchase = VehiclePurchase(real.service);
      final offer = vehicleOffer(
        real.content,
        PlayerProgress.empty,
        real.service.view.jenehat,
        VehicleId.microOld,
      )!;
      final first = purchase.buy(offer);
      expect(await purchase.buy(offer), isNull);
      expect(await first, isA<OpApplied>());
      expect(real.service.view.jenehat, 500);
      expect(real.service.view.owns(SkuKind.vehicle, 'micro_old'), isTrue);
    });
  });
}

/// Matches an [OpRefused] with [code].
Matcher _refused(EconomyRefusal code) =>
    isA<OpRefused>().having((o) => o.code, 'code', code);
