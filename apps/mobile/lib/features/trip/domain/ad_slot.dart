// What a trip's rewarded-ad button shows (specs/018-m11-ads,
// contracts/seams.md "`TripAdOffers`"): the failure card's revive and the
// «زحمة» card's ad. The ads layer answers it from its caches, so the trip
// may ask at any time (research R7).

/// [hidden] draws nothing; the others draw the button, tappable only when
/// [ready].
enum AdSlot {
  hidden,
  ready,
  notReady,
  offline;

  bool get shown => this != hidden;
}
