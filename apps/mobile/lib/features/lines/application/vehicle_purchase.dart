// Buying a vehicle from its sheet (specs/014-m09-lines-vehicles,
// contracts/buy-vehicle.md "Buying", research R6): one request id held per
// intent, so a double tap buys once and a retry after a failed write sends
// the same request (M05 R10), as M08's BoosterPurchase. The economy reads
// the price from the catalog; the caller never passes one. Offline, it
// applies at once and M06 syncs it later.
import 'package:content_models/content_models.dart';
import 'package:wassal/core/economy/domain/wire.dart';
import 'package:wassal/core/economy/economy.dart';
import 'package:wassal/core/progress/domain/playable.dart';
import 'package:wassal/features/lines/domain/vehicle_offer.dart';

/// One per open sheet.
final class VehiclePurchase {
  VehiclePurchase(this._economy);

  final Economy _economy;
  TxnId? _id;
  bool _busy = false;

  /// A call is in flight.
  bool get busy => _busy;

  /// Buys [offer]'s vehicle. Null, with no call, while a call is in flight
  /// or unless it is for sale and affordable.
  Future<OpOutcome?> buy(VehicleOffer offer) async {
    if (_busy || offer.sale is! ForSale || !offer.affordable) return null;
    _busy = true;
    try {
      final id = _id ??= _economy.newRequestId();
      final outcome = await _economy.buy(
        id,
        kind: SkuKind.vehicle,
        skuId: vehicleWire[offer.vehicle]!,
      );
      // The id goes with an intent that is over: bought, owned already, or
      // not for sale. Short of money or a failed write, a retry is the same
      // intent.
      if (switch (outcome) {
        OpApplied() => true,
        OpRefused(:final code) => _over.contains(code),
        OpWriteFailed() => false,
      }) {
        _id = null;
      }
      return outcome;
    } finally {
      _busy = false;
    }
  }

  static const _over = {
    EconomyRefusal.alreadyOwned,
    EconomyRefusal.notForSale,
    EconomyRefusal.unknownSku,
    EconomyRefusal.catalogMismatch,
    EconomyRefusal.unknownVariant,
  };
}
