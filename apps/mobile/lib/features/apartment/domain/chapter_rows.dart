// The timeline's rows (specs/015-m10-apartment-story, data-model "Apartment",
// contracts/scene-viewer.md "The timeline", research R13): the seven chapters
// of the glossary, each done, current or locked, whether or not the pack has
// it. Pure.
import 'package:content_models/content_models.dart';
import 'package:wassal/core/content/domain/content_source.dart';
import 'package:wassal/core/progress/domain/player_progress.dart';
import 'package:wassal/core/progress/domain/story.dart';
import 'package:wassal/core/progress/domain/unlocks.dart';
import 'package:wassal/features/home/domain/savings_target.dart';
import 'package:wassal/features/story/domain/panel_ref.dart';
import 'package:wassal/features/story/domain/scene_sequence.dart';

/// What the current chapter still asks of the player.
sealed class CurrentGoal {
  const CurrentGoal();
}

/// A room: the pieces owned of all, the pieces' names and the goal scene's
/// title, when the chapter has one.
final class RoomGoal extends CurrentGoal {
  const RoomGoal({
    required this.owned,
    required this.total,
    required this.itemNames,
    required this.sceneTitle,
  });

  final int owned;
  final int total;
  final List<String> itemNames;
  final String? sceneTitle;

  @override
  bool operator ==(Object other) =>
      other is RoomGoal &&
      other.owned == owned &&
      other.total == total &&
      other.sceneTitle == sceneTitle &&
      _same(other.itemNames, itemNames);

  @override
  int get hashCode =>
      Object.hash(owned, total, sceneTitle, Object.hashAll(itemNames));

  @override
  String toString() => 'RoomGoal($owned/$total, $itemNames, $sceneTitle)';
}

/// A vehicle or a purchase: JENEHAT saved of the price.
final class AmountGoal extends CurrentGoal {
  const AmountGoal({required this.title, required this.have, required this.of});

  /// What the goal names, as the content names it.
  final String title;
  final int have;
  final int of;

  @override
  bool operator ==(Object other) =>
      other is AmountGoal &&
      other.title == title &&
      other.have == have &&
      other.of == of;

  @override
  int get hashCode => Object.hash(title, have, of);

  @override
  String toString() => 'AmountGoal($title, $have/$of)';
}

/// A line: trips finished of its regular trips.
final class CountGoal extends CurrentGoal {
  const CountGoal({required this.title, required this.done, required this.of});

  final String title;
  final int done;
  final int of;

  @override
  bool operator ==(Object other) =>
      other is CountGoal &&
      other.title == title &&
      other.done == done &&
      other.of == of;

  @override
  int get hashCode => Object.hash(title, done, of);

  @override
  String toString() => 'CountGoal($title, $done/$of)';
}

sealed class ChapterRow {
  const ChapterRow({
    required this.chapterId,
    required this.number,
    required this.name,
  });

  final ChapterId chapterId;

  /// The chapter's place in the glossary, from 1.
  final int number;

  /// The pack's title, or null for a chapter the pack lacks: the screen
  /// names it from its strings.
  final String? name;
}

/// A complete chapter: the first panel of its last unlocked scene, and
/// whether there is a scene to watch at all.
final class DoneRow extends ChapterRow {
  const DoneRow({
    required super.chapterId,
    required super.number,
    required super.name,
    required this.thumb,
    required this.hasScenes,
    required this.sceneTitle,
  });

  final PanelRef? thumb;
  final bool hasScenes;

  /// The title of the scene «شوف المشهد» opens (its last unlocked one).
  final String? sceneTitle;
}

/// The chapter the player is in. [goal] is null when the pack can't say what
/// it asks (a goal naming a line, vehicle or room it lacks).
final class CurrentRow extends ChapterRow {
  const CurrentRow({
    required super.chapterId,
    required super.number,
    required super.name,
    required this.goal,
    this.line,
  });

  final CurrentGoal? goal;

  /// What the chapter's character says of the goal, for a goal that is not
  /// a room (the pack's `goal_line`).
  final String? line;
}

final class LockedRow extends ChapterRow {
  const LockedRow({
    required super.chapterId,
    required super.number,
    required super.name,
  });
}

/// The seven rows for [p] holding [jenehat], by the glossary's order. At the
/// end of the pack's story there is no [CurrentRow].
List<ChapterRow> chapterRows(
  ContentSource c,
  PlayerProgress p, {
  required int jenehat,
}) {
  final current = _currentUnlessEnded(c, p);
  return [
    for (final (index, id) in ChapterId.values.indexed)
      _row(c, p, jenehat, id, index + 1, current),
  ];
}

ChapterRow _row(
  ContentSource c,
  PlayerProgress p,
  int jenehat,
  ChapterId id,
  int number,
  Chapter? current,
) {
  final chapter = c.chapter(id);
  if (chapter == null) {
    return LockedRow(chapterId: id, number: number, name: null);
  }
  final name = chapter.title.arEg;
  if (chapterComplete(c, p, id)) {
    final scenes = sceneSequence(c, p, chapter);
    return DoneRow(
      chapterId: id,
      number: number,
      name: name,
      thumb: scenes.isEmpty ? null : PanelRef.of(scenes.last.panels.first),
      hasScenes: scenes.isNotEmpty,
      sceneTitle: scenes.isEmpty ? null : scenes.last.title.arEg,
    );
  }
  if (current?.chapterId == id) {
    return CurrentRow(
      chapterId: id,
      number: number,
      name: name,
      goal: _goalOf(c, p, chapter, jenehat),
      line: chapter.goalLine?.text.arEg,
    );
  }
  return LockedRow(chapterId: id, number: number, name: name);
}

/// The current chapter, or null for a pack without chapters and once the
/// pack's last one is complete.
Chapter? _currentUnlessEnded(ContentSource c, PlayerProgress p) {
  final order = chaptersInOrder(c);
  if (order.isEmpty || chapterComplete(c, p, order.last.chapterId)) return null;
  return currentChapter(c, p);
}

CurrentGoal? _goalOf(
  ContentSource c,
  PlayerProgress p,
  Chapter chapter,
  int jenehat,
) {
  if (chapter.goal.kind == GoalKind.completeRoom) {
    final roomId = chapter.goal.roomId;
    final room = roomId == null ? null : c.room(roomId);
    if (room == null) return null;
    final items = [...c.itemsOf(room.roomId)]
      ..sort((a, b) => a.order.compareTo(b.order));
    return RoomGoal(
      owned: items.where((i) => p.owns(SkuKind.item, i.itemId)).length,
      total: items.length,
      itemNames: [for (final item in items) item.name.arEg],
      sceneTitle: goalSceneOf(chapter)?.title.arEg,
    );
  }
  final target = savingsTarget(c, p, jenehat);
  if (target is! ChapterGoalTarget ||
      target.chapter.chapterId != chapter.chapterId) {
    return null;
  }
  final title = target.subjectName;
  return switch (target.progress) {
    Amount(:final have, :final of) => AmountGoal(
      title: title,
      have: have,
      of: of,
    ),
    Count(:final done, :final of) => CountGoal(
      title: title,
      done: done,
      of: of,
    ),
  };
}

bool _same(List<String> a, List<String> b) =>
    a.length == b.length &&
    [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((same) => same);
