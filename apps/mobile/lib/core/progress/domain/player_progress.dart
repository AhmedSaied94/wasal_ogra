// What the progression rules read of a player (specs/013-m08-home-result,
// contracts/progress-rules.md "Inputs"), as the server's `PlayerView` is.
// The application layer builds it from the economy's view.
import 'package:content_models/content_models.dart';

final class PlayerProgress {
  const PlayerProgress({this.bestStars = const {}, this.owned = const {}});

  /// A new player: nothing finished, nothing owned.
  static const empty = PlayerProgress();

  /// By trip id; a missing trip has 0.
  final Map<String, int> bestStars;

  /// `(vehicle | item | chapter, sku id)`, the ids as the catalog writes them.
  final Set<(SkuKind, String)> owned;

  int starsOf(String tripId) => bestStars[tripId] ?? 0;

  /// The server's "finished": at least one star.
  bool finished(String tripId) => starsOf(tripId) >= 1;

  bool owns(SkuKind kind, String skuId) => owned.contains((kind, skuId));
}
