// The scenes a chapter's viewer plays (specs/015-m10-apartment-story,
// contracts/scene-viewer.md "Routes"): its unlocked scenes in story order,
// one after another. Pure.
import 'package:content_models/content_models.dart';
import 'package:wassal/core/content/domain/content_source.dart';
import 'package:wassal/core/progress/domain/player_progress.dart';
import 'package:wassal/core/progress/domain/story.dart';

/// What `/story/scene/:sceneId` plays: that scene when the pack has it and
/// it is unlocked, else nothing.
List<(Chapter, Scene)> sequenceOfScene(
  ContentSource content,
  PlayerProgress progress,
  String sceneId,
) => [
  for (final chapter in content.chapters)
    for (final scene in chapter.scenes)
      if (scene.sceneId == sceneId &&
          sceneUnlocked(content, progress, chapter, scene))
        (chapter, scene),
];

/// What `/story/:chapterId` plays: the chapter's unlocked scenes in order;
/// nothing for a chapter the pack lacks.
List<(Chapter, Scene)> sequenceOfChapter(
  ContentSource content,
  PlayerProgress progress,
  ChapterId chapterId,
) {
  final chapter = content.chapter(chapterId);
  if (chapter == null) return const [];
  return [
    for (final scene in sceneSequence(content, progress, chapter))
      (chapter, scene),
  ];
}

/// [chapter]'s scenes the player may watch now: the unlocked ones, in the
/// chapter's own order. A locked chapter's single goal scene isn't one, so
/// the list is empty and the viewer leaves.
List<Scene> sceneSequence(
  ContentSource content,
  PlayerProgress progress,
  Chapter chapter,
) => [
  for (final scene in chapter.scenes)
    if (sceneUnlocked(content, progress, chapter, scene)) scene,
];
