// The rewards on their way, from the two states (specs/015-m10-apartment-story,
// contracts/economy-ops.md "Pending rewards").
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wassal/core/content/content_providers.dart';
import 'package:wassal/core/economy/economy_providers.dart';
import 'package:wassal/core/progress/application/player_progress_provider.dart';
import 'package:wassal/core/progress/domain/rewards.dart';

/// [pendingRewards] over the projection and the confirmed base. A keepAlive
/// provider: both views, the rooms' header and `RoomDone` read it.
final pendingRewardsProvider = Provider<List<PendingReward>>((ref) {
  final content = ref.watch(contentSourceProvider);
  final view = ref.watch(economyViewProvider);
  return pendingRewards(
    content,
    playerProgressOf(view, content),
    playerProgressOfConfirmed(view.confirmed, content),
    view.requestsClaimed,
    view.confirmed.requestsClaimed,
  );
});

/// [pendingTotal] of [pendingRewardsProvider], for the header's chip.
final pendingRewardTotalProvider = Provider<int>(
  (ref) => pendingTotal(ref.watch(pendingRewardsProvider)),
);
