// What the apartment tab shows (specs/015-m10-apartment-story, data-model
// "Apartment", contracts/apartment.md "The tab"): the goal view before the
// apartment opens, then the current room's view.
import 'package:content_models/content_models.dart';
import 'package:wassal/core/content/domain/content_source.dart';
import 'package:wassal/core/progress/domain/player_progress.dart';
import 'package:wassal/core/progress/domain/unlocks.dart';
import 'package:wassal/features/apartment/domain/goal_view_model.dart';
import 'package:wassal/features/apartment/domain/room_model.dart';

/// The tab's two views.
sealed class ApartmentView {
  const ApartmentView();
}

/// Before the apartment opens: the current chapter's goal. The model is
/// null for a pack with no chapter and no room.
final class GoalView extends ApartmentView {
  const GoalView([this.model]);

  final GoalViewModel? model;
}

/// From the apartment's chapter on: the current room, and whether the story
/// ends here.
final class RoomsView extends ApartmentView {
  const RoomsView({required this.model, required this.storyEnd});

  final RoomModel model;
  final bool storyEnd;
}

/// [content]'s tab for [progress] at [jenehat] (contracts/apartment.md "The
/// tab"). The pending chip's total is passed through to the rooms view's
/// header.
ApartmentView apartmentViewOf(
  ContentSource content,
  PlayerProgress progress, {
  required int jenehat,
  required String? Function(String itemId) variantOf,
  required Set<String> requestsClaimed,
  required Map<String, Set<String>> scenesSeen,
  required int pendingTotal,
}) {
  final opens = apartmentOpens(content);
  final chapter = currentChapter(content, progress);
  final open = opens != null && chapter != null && chapter.order >= opens.order;
  if (!open) return GoalView(goalViewModelOf(content, progress, jenehat));
  // `open` needs a current chapter, so the room is always on one.
  final storyEnd = _endsStory(content, progress, chapter);
  final model = roomModel(
    content,
    progress,
    chapter,
    jenehat: jenehat,
    variantOf: variantOf,
    requestsClaimed: requestsClaimed,
    scenesSeen: scenesSeen,
    pendingTotal: pendingTotal,
  );
  if (model == null) return const GoalView();
  return RoomsView(model: model, storyEnd: storyEnd);
}

/// The current chapter is the last one and complete: the end of the story.
bool _endsStory(
  ContentSource content,
  PlayerProgress progress,
  Chapter chapter,
) {
  final order = chaptersInOrder(content);
  if (order.isEmpty || order.last.chapterId != chapter.chapterId) return false;
  return chapterComplete(content, progress, chapter.chapterId);
}
