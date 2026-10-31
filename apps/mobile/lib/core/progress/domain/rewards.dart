// The rewards on their way (specs/015-m10-apartment-story,
// contracts/economy-ops.md "Pending rewards", research R6). Pure.
//
// The phone never adds BONAT (constitution IV): a room's, a chapter's or a
// request's reward shows «في الطريق» until the confirmed base carries it.
// The projection tells whether it is due; the base, whether the server paid.
import 'package:content_models/content_models.dart';
import 'package:wassal/core/content/domain/content_source.dart';
import 'package:wassal/core/progress/domain/player_progress.dart';
import 'package:wassal/core/progress/domain/unlocks.dart';

sealed class RewardSource {
  const RewardSource();
}

final class RoomReward extends RewardSource {
  const RoomReward(this.roomId);

  final RoomId roomId;

  @override
  bool operator ==(Object other) =>
      other is RoomReward && other.roomId == roomId;

  @override
  int get hashCode => Object.hash(RoomReward, roomId);

  @override
  String toString() => 'RoomReward($roomId)';
}

final class ChapterReward extends RewardSource {
  const ChapterReward(this.chapterId);

  final ChapterId chapterId;

  @override
  bool operator ==(Object other) =>
      other is ChapterReward && other.chapterId == chapterId;

  @override
  int get hashCode => Object.hash(ChapterReward, chapterId);

  @override
  String toString() => 'ChapterReward($chapterId)';
}

final class RequestReward extends RewardSource {
  const RequestReward(this.requestId);

  final String requestId;

  @override
  bool operator ==(Object other) =>
      other is RequestReward && other.requestId == requestId;

  @override
  int get hashCode => Object.hash(RequestReward, requestId);

  @override
  String toString() => 'RequestReward($requestId)';
}

final class PendingReward {
  const PendingReward(this.source, this.bonat);

  final RewardSource source;
  final int bonat;

  @override
  bool operator ==(Object other) =>
      other is PendingReward && other.source == source && other.bonat == bonat;

  @override
  int get hashCode => Object.hash(source, bonat);

  @override
  String toString() => 'PendingReward($source, $bonat BONAT)';
}

/// Every reward the projection completes and the confirmed base doesn't
/// have, in content order: rooms, chapters, then requests.
///
/// A new player before the first sync has an empty base, so every completion
/// is pending until then.
List<PendingReward> pendingRewards(
  ContentSource c,
  PlayerProgress projection,
  PlayerProgress confirmed,
  Set<String> claimed,
  Set<String> claimedConfirmed,
) => [
  for (final room in c.rooms)
    if (roomComplete(c, projection, room.roomId) &&
        !roomComplete(c, confirmed, room.roomId))
      PendingReward(RoomReward(room.roomId), room.completionBonat),
  for (final chapter in chaptersInOrder(c))
    if (chapterComplete(c, projection, chapter.chapterId) &&
        !chapterComplete(c, confirmed, chapter.chapterId))
      PendingReward(ChapterReward(chapter.chapterId), chapter.completionBonat),
  for (final request in c.familyRequests)
    if (claimed.contains(request.requestId) &&
        !claimedConfirmed.contains(request.requestId))
      PendingReward(RequestReward(request.requestId), request.rewardBonat),
];

/// The sum of [rewards]' BONAT.
int pendingTotal(List<PendingReward> rewards) =>
    rewards.fold(0, (sum, reward) => sum + reward.bonat);
