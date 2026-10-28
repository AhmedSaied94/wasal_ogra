// The between-trips checkpoint (specs/013-m08-home-result, contracts/
// seams.md, research R10): M11 shows its interstitial here. Until then it
// lets the player through at once.
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'checkpoint.g.dart';

abstract interface class BetweenTripsCheckpoint {
  /// Called before the pre-trip card, or a direct trip start, from Home and
  /// «مشوار تاني». Never after «اطلع», never while a trip runs
  /// (constitution IX).
  Future<void> pass();
}

/// The default: nothing between trips.
final class OpenCheckpoint implements BetweenTripsCheckpoint {
  const OpenCheckpoint();

  @override
  Future<void> pass() async {}
}

@Riverpod(keepAlive: true)
BetweenTripsCheckpoint betweenTripsCheckpoint(Ref ref) =>
    const OpenCheckpoint();
