// Buying a booster from the card (specs/013-m08-home-result, research R7):
// one request id held from the tap until the outcome, so a double tap buys
// once and a retry after a failed write sends the same request (M05 R10).
// It works offline: BONAT spends are optimistic up to the local balance.
import 'package:content_models/content_models.dart';
import 'package:wassal/core/economy/domain/wire.dart';
import 'package:wassal/core/economy/economy.dart';

/// One per open card.
final class BoosterPurchase {
  BoosterPurchase(this._economy);

  final Economy _economy;
  TxnId? _id;
  bool _busy = false;

  /// A call is in flight.
  bool get busy => _busy;

  /// Buys one [booster]. Null when a call is already in flight, which this
  /// tap leaves alone. Applied clears the held id; a refusal or a failed
  /// write keeps it, so the next try is the same request.
  Future<OpOutcome?> buy(BoosterId booster) async {
    if (_busy) return null;
    _busy = true;
    try {
      final id = _id ??= _economy.newRequestId();
      final outcome = await _economy.buy(
        id,
        kind: SkuKind.booster,
        skuId: boosterWire[booster]!,
      );
      if (outcome is OpApplied) _id = null;
      return outcome;
    } finally {
      _busy = false;
    }
  }
}
