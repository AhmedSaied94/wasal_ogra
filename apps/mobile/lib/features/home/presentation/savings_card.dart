// Home's savings card (specs/013-m08-home-result, contracts/home.md,
// research R4, HANDOFF `C-Home` block 5, `HomeStates` block 6): the next
// piece of the apartment, or before it opens the chapter's goal; «جاهزة
// للشرا!» when affordable, and «مشهد جديد مستنيك» in the bar's place while a
// scene waits (M10). Opens the apartment.
import 'package:content_models/content_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/l10n/number_formatter.dart';
import 'package:wassal/core/routing/nav_guard.dart';
import 'package:wassal/core/theme/components/app_icon.dart';
import 'package:wassal/core/theme/components/containers.dart';
import 'package:wassal/core/theme/components/pressable.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/home/domain/savings_target.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

/// [target]'s goal as a title: «اشتري الميكروباص القديم».
String goalTitle(AppLocalizations l10n, ChapterGoalTarget target) =>
    switch (target.goalKind) {
      GoalKind.completeLine => l10n.goalCompleteLine(target.subjectName),
      GoalKind.ownVehicle => l10n.goalOwnVehicle(target.subjectName),
      GoalKind.purchase => l10n.goalPurchase(target.subjectName),
      GoalKind.completeRoom => l10n.goalCompleteRoom(target.subjectName),
    };

/// [target]'s glyph in its tile: what the goal asks for (HANDOFF §11
/// `HomeStates` block 6): the line's route, the vehicle, the ring, the
/// room.
Widget goalGlyph(ChapterGoalTarget target, {required double size}) =>
    switch (target.goalKind) {
      GoalKind.completeLine => AppIcon(
        'route_bold',
        size: size,
        color: ColorTokens.primary,
      ),
      GoalKind.ownVehicle => AppIcon(
        'nav_home',
        size: size,
        color: ColorTokens.primary,
      ),
      GoalKind.purchase => AppIcon('ring_gem', size: size),
      GoalKind.completeRoom => AppIcon(
        'nav_apartment',
        size: size,
        color: ColorTokens.primary,
      ),
    };

/// [progress] as figures: «١٬٢٤٠ / ٣٬٢٠٠ ج», or «١/٢» for trips.
String progressFigures(
  AppLocalizations l10n,
  NumberFormatter numbers,
  SavingsProgress progress,
) => switch (progress) {
  Amount(:final have, of: final price) => l10n.homeSavingsAmount(
    numbers.integer(have),
    numbers.integer(price),
  ),
  Count(:final done, of: final total) => numbers.ratio(done, total),
};

class HomeSavingsCard extends ConsumerWidget {
  const HomeSavingsCard({
    required this.target,
    required this.sceneWaiting,
    super.key,
  });

  final SavingsTarget target;
  final bool sceneWaiting;

  static const double height = 84;
  static const readyKey = Key('HomeSavingsCard.ready');

  static const double _tile = 54;
  static const double _tileIcon = 32;
  static const double _lock = 14;
  static const double _rowGap = 4;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final numbers = ref.watch(numberFormatterProvider);
    final (
      :title,
      :chapter,
      :note,
      :figures,
      :fraction,
      :label,
      :goal,
    ) = switch (target) {
      ApartmentPieceTarget(
        :final chapter,
        :final itemName,
        :final progress,
        :final affordable,
      ) =>
        (
          title: l10n.homeSavingsTitle,
          chapter: chapter.order,
          note: l10n.homeSavingsNext(itemName),
          figures: progressFigures(l10n, numbers, progress),
          fraction: progress.fraction,
          label: (affordable
              ? l10n.homeA11ySavingsReady
              : l10n.homeA11ySavings)(numbers.integer(chapter.order), itemName),
          goal: false,
        ),
      final ChapterGoalTarget goal => (
        title: goalTitle(l10n, goal),
        chapter: goal.chapter.order,
        note: switch (goal.opensInChapter) {
          final opens? => l10n.homeGoalApartmentLocked(numbers.integer(opens)),
          null => null,
        },
        figures: progressFigures(l10n, numbers, goal.progress),
        fraction: goal.progress.fraction,
        label: l10n.homeA11yGoal(
          numbers.integer(goal.chapter.order),
          goalTitle(l10n, goal),
        ),
        goal: true,
      ),
      NoTarget() => throw StateError('no savings target'),
    };
    final radius = BorderRadius.circular(RadiusTokens.card);
    final ready = target.affordable;
    return Pressable(
      onTap: () => NavGuard.go(context, '/apartment'),
      lip: LipTokens.card,
      borderRadius: radius,
      semanticLabel: label,
      child: Container(
        constraints: const BoxConstraints(minHeight: height),
        padding: const EdgeInsets.symmetric(horizontal: SpaceTokens.s14),
        decoration: BoxDecoration(
          color: ColorTokens.paper,
          borderRadius: radius,
        ),
        child: Row(
          spacing: SpaceTokens.s12,
          children: [
            Container(
              width: _tile,
              height: _tile,
              decoration: BoxDecoration(
                color: goal ? ColorTokens.primarySoft : ColorTokens.sunSoft,
                borderRadius: BorderRadius.circular(RadiusTokens.bubble),
              ),
              alignment: Alignment.center,
              child: switch (target) {
                final ChapterGoalTarget goal => goalGlyph(
                  goal,
                  size: _tileIcon,
                ),
                _ => const AppIcon('ring_gem', size: _tileIcon),
              },
            ),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: _rowGap,
                children: [
                  _Row(
                    start: Text(
                      title,
                      style: TypeTokens.displayS.copyWith(
                        color: ColorTokens.ink,
                      ),
                    ),
                    end: Text(
                      l10n.homeSavingsChapter(numbers.integer(chapter)),
                      style: TypeTokens.label.copyWith(
                        color: ColorTokens.inkMuted,
                      ),
                    ),
                  ),
                  _Row(
                    start: switch (note) {
                      final note? when goal => Row(
                        mainAxisSize: MainAxisSize.min,
                        spacing: SpaceTokens.s4,
                        children: [
                          const AppIcon(
                            'lock',
                            size: _lock,
                            color: ColorTokens.inkMuted,
                          ),
                          Flexible(
                            child: Text(
                              note,
                              style: TypeTokens.caption.copyWith(
                                color: ColorTokens.inkMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                      final note? => Text(
                        note,
                        style: TypeTokens.body.copyWith(color: ColorTokens.ink),
                      ),
                      null => const SizedBox.shrink(),
                    },
                    end: ready
                        ? Text(
                            l10n.homeSavingsReady,
                            key: readyKey,
                            style: TypeTokens.body
                                .weight(700)
                                .copyWith(color: ColorTokens.primary),
                          )
                        : Text(
                            figures,
                            style: (goal ? TypeTokens.caption : TypeTokens.body)
                                .weight(700)
                                .copyWith(color: ColorTokens.ink),
                          ),
                  ),
                  if (sceneWaiting)
                    Text(
                      l10n.homeSceneWaiting,
                      style: TypeTokens.caption
                          .weight(700)
                          .copyWith(color: ColorTokens.primary),
                    )
                  else
                    ProgressBar(value: fraction, color: ProgressColor.gold),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// [start] at the start and [end] at the end, on one line as drawn; [end]
/// goes under [start] when both don't fit (large text), so nothing is cut.
class _Row extends StatelessWidget {
  const _Row({required this.start, required this.end});

  final Widget start;
  final Widget end;

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.spaceBetween,
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: SpaceTokens.s8,
    children: [start, end],
  );
}
