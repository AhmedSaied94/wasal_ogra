// What the purchase leaves for the savings goal (specs/014-m09-lines-
// vehicles, contracts/buy-vehicle.md "The offer", research R7): M08's
// savings target for the player after the purchase, and what it still
// lacks. «بعد الشرا، فاضل {amount} ج على {goal}».
import 'package:content_models/content_models.dart';
import 'package:wassal/core/content/domain/content_source.dart';
import 'package:wassal/core/economy/domain/wire.dart';
import 'package:wassal/core/progress/domain/playable.dart';
import 'package:wassal/core/progress/domain/player_progress.dart';
import 'package:wassal/features/home/domain/savings_target.dart';

final class Impact {
  const Impact({required this.goalName, required this.amount});

  /// As the pack names it.
  final String goalName;

  /// JENEHAT still missing after the purchase; always above 0.
  final int amount;

  @override
  bool operator ==(Object other) =>
      other is Impact && other.goalName == goalName && other.amount == amount;

  @override
  int get hashCode => Object.hash(goalName, amount);

  @override
  String toString() => 'Impact($goalName, $amount)';
}

/// Null when the vehicle isn't for sale, the purchase isn't affordable, the
/// goal has no price (a line to finish, nothing left), or nothing is
/// missing (FR-032).
Impact? impactAfterPurchase(
  ContentSource c,
  PlayerProgress p,
  int jenehat,
  VehicleId vehicle,
) {
  final price = switch (vehicleSale(c, p, vehicle)) {
    ForSale(:final priceJenehat) => priceJenehat,
    _ => null,
  };
  if (price == null || jenehat < price) return null;
  final after = PlayerProgress(
    bestStars: p.bestStars,
    owned: {...p.owned, (SkuKind.vehicle, vehicleWire[vehicle]!)},
  );
  final left = jenehat - price;
  final (name, goalPrice) = switch (savingsTarget(c, after, left)) {
    ChapterGoalTarget(:final subjectName, progress: Amount(:final of)) => (
      subjectName,
      of,
    ),
    ApartmentPieceTarget(:final itemName, :final priceJenehat) => (
      itemName,
      priceJenehat,
    ),
    _ => (null, 0),
  };
  if (name == null) return null;
  final amount = goalPrice - left;
  return amount > 0 ? Impact(goalName: name, amount: amount) : null;
}
