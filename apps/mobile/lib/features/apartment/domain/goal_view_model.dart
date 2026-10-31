// The apartment's goal view (specs/015-m10-apartment-story, contracts/
// apartment.md "The goal view", research R8): the current chapter's goal
// over M08's `savingsTarget`, its art, its line and what its CTA does.
// Pure; the screen reads it from `apartmentViewProvider`.
import 'package:content_models/content_models.dart';
import 'package:wassal/core/content/domain/content_source.dart';
import 'package:wassal/core/economy/domain/wire.dart';
import 'package:wassal/core/progress/domain/player_progress.dart';
import 'package:wassal/core/progress/domain/unlocks.dart';
import 'package:wassal/features/home/domain/savings_target.dart';

/// The goal card's drawing: the author's `goal_art`, else the goal kind's
/// fallback (research R17).
sealed class GoalArt {
  const GoalArt();
}

/// The author's drawing, by `Chapter.goal_art`. The screen resolves the slug
/// through `ApartmentArt.goal`, and draws [GoalViewModel.fallbackArt] when
/// the app doesn't ship it (art lives in the app, not in packs).
final class DrawnGoal extends GoalArt {
  const DrawnGoal(this.slug);

  final String slug;

  @override
  bool operator ==(Object other) => other is DrawnGoal && other.slug == slug;

  @override
  int get hashCode => Object.hash(DrawnGoal, slug);
}

/// The vehicle the goal names.
final class VehicleGoal extends GoalArt {
  const VehicleGoal(this.vehicleId);

  final VehicleId vehicleId;

  @override
  bool operator ==(Object other) =>
      other is VehicleGoal && other.vehicleId == vehicleId;

  @override
  int get hashCode => Object.hash(VehicleGoal, vehicleId);
}

/// The line's tuktuk (a `complete_line` goal).
final class TuktukGoal extends GoalArt {
  const TuktukGoal();

  @override
  bool operator ==(Object other) => other is TuktukGoal;

  @override
  int get hashCode => Object.hash(TuktukGoal, 0);
}

/// The ring: a purchase's fallback.
final class RingGoal extends GoalArt {
  const RingGoal();

  @override
  bool operator ==(Object other) => other is RingGoal;

  @override
  int get hashCode => Object.hash(RingGoal, 1);
}

/// What the CTA does in the ready state.
sealed class GoalAction {
  const GoalAction();
}

final class NoAction extends GoalAction {
  const NoAction();

  @override
  bool operator ==(Object other) => other is NoAction;

  @override
  int get hashCode => Object.hash(NoAction, 0);
}

/// `purchase`: the chapter's own price, bought by `GoalPurchase`.
final class BuyChapter extends GoalAction {
  const BuyChapter(this.price);

  final int price;

  @override
  bool operator ==(Object other) => other is BuyChapter && other.price == price;

  @override
  int get hashCode => Object.hash(BuyChapter, price);
}

/// `own_vehicle`: M09's vehicle sheet, which does the buying.
final class OpenVehicleSheet extends GoalAction {
  const OpenVehicleSheet(this.vehicleId, {this.price = 0});

  final VehicleId vehicleId;

  /// The vehicle's JENEHAT price, for the CTA's chip (0 when the pack has
  /// none).
  final int price;

  @override
  bool operator ==(Object other) =>
      other is OpenVehicleSheet &&
      other.vehicleId == vehicleId &&
      other.price == price;

  @override
  int get hashCode => Object.hash(OpenVehicleSheet, vehicleId, price);
}

/// The outline of [chapter]'s goal card.
final class GoalViewModel {
  const GoalViewModel({
    required this.chapter,
    required this.target,
    required this.art,
    required this.fallbackArt,
    required this.action,
    required this.ready,
    this.line,
  });

  final Chapter chapter;
  final ChapterGoalTarget target;

  /// The author's `goal_art` when there is one, else [fallbackArt].
  final GoalArt art;

  /// The goal kind's own drawing, for a `goal_art` the app doesn't ship.
  final GoalArt fallbackArt;
  final GoalAction action;

  /// The bar covers the price and the chapter isn't met yet.
  final bool ready;

  /// `goal_line`, its text replaced by `ready_line` when ready.
  final CharacterLine? line;

  /// The grammatical gender of what the goal names, for «جاهز» and «جاهزة»
  /// (`AptGoalVehicle`): `m` for a vehicle (الميكروباص), else `f` (الشبكة).
  String get genderCode => chapter.goal.kind == GoalKind.ownVehicle ? 'm' : 'f';

  @override
  bool operator ==(Object other) =>
      other is GoalViewModel &&
      other.chapter.chapterId == chapter.chapterId &&
      other.target == target &&
      other.art == art &&
      other.fallbackArt == fallbackArt &&
      other.action == action &&
      other.ready == ready &&
      other.line?.speaker == line?.speaker &&
      other.line?.text == line?.text;

  @override
  int get hashCode => Object.hash(
    chapter.chapterId,
    target,
    art,
    fallbackArt,
    action,
    ready,
    line?.speaker,
    line?.text,
  );

  @override
  String toString() =>
      'GoalViewModel(${chapter.chapterId.name}, ${target.goalKind.name}, '
      'ready $ready)';
}

/// [chapter]'s goal card over [target] (M08's), or null for a goal that has
/// none (a room's, which the rooms view draws).
GoalViewModel? goalViewModel(
  ContentSource c,
  PlayerProgress p,
  Chapter chapter,
  ChapterGoalTarget target,
) {
  if (target.goalKind == GoalKind.completeRoom) return null;
  final ready = target.affordable && !_owned(c, p, chapter);
  final line = _line(chapter, ready: ready);
  final fallback = _fallbackArt(chapter);
  return GoalViewModel(
    chapter: chapter,
    target: target,
    art: chapter.goalArt == null ? fallback : DrawnGoal(chapter.goalArt!),
    fallbackArt: fallback,
    action: _action(c, chapter),
    ready: ready,
    line: line,
  );
}

/// The chapter's goal card for [chapter] over [jenehat], or null when it
/// has none.
GoalViewModel? goalViewModelOf(ContentSource c, PlayerProgress p, int jenehat) {
  final chapter = currentChapter(c, p);
  if (chapter == null) return null;
  final target = savingsTarget(c, p, jenehat);
  if (target is! ChapterGoalTarget) return null;
  return goalViewModel(c, p, chapter, target);
}

/// Whether [chapter]'s goal is already met: its vehicle owned, the chapter
/// bought.
bool _owned(ContentSource c, PlayerProgress p, Chapter chapter) =>
    switch (chapter.goal.kind) {
      GoalKind.purchase => p.owns(
        SkuKind.chapter,
        chapterWire[chapter.chapterId]!,
      ),
      GoalKind.ownVehicle => switch (chapter.goal.vehicleId) {
        final id? => vehicleOwned(c, p, id),
        null => false,
      },
      // A line's goal is a count, never ready; a room is the rooms view.
      GoalKind.completeLine || GoalKind.completeRoom => false,
    };

GoalArt _fallbackArt(Chapter chapter) => switch (chapter.goal.kind) {
  GoalKind.ownVehicle => switch (chapter.goal.vehicleId) {
    final id? => VehicleGoal(id),
    null => const RingGoal(),
  },
  GoalKind.completeLine => const TuktukGoal(),
  GoalKind.purchase || GoalKind.completeRoom => const RingGoal(),
};

GoalAction _action(ContentSource c, Chapter chapter) =>
    switch (chapter.goal.kind) {
      GoalKind.purchase => switch (c.price(
        SkuKind.chapter,
        chapterWire[chapter.chapterId]!,
      )) {
        CatalogPrice(currency: Currency.jenehat, :final amount) => BuyChapter(
          amount,
        ),
        _ => const NoAction(),
      },
      GoalKind.ownVehicle => switch (chapter.goal.vehicleId) {
        final id? => OpenVehicleSheet(
          id,
          price: switch (c.price(SkuKind.vehicle, vehicleWire[id]!)) {
            CatalogPrice(currency: Currency.jenehat, :final amount) => amount,
            _ => 0,
          },
        ),
        null => const NoAction(),
      },
      GoalKind.completeLine || GoalKind.completeRoom => const NoAction(),
    };

CharacterLine? _line(Chapter chapter, {required bool ready}) {
  final goal = chapter.goalLine;
  if (goal == null) return null;
  final replacement = ready ? chapter.readyLine : null;
  return replacement == null
      ? goal
      : CharacterLine(speaker: goal.speaker, text: replacement);
}
