// The HUD (HANDOFF §4.3, `C-Trip` boxes 1–23): a 44 pt row with pause at the
// start, the line and trip title, and reputation at the end; the station
// strip under it. Pause, and on internal builds the debug panel's button
// beside it, are the only controls up here: both stop play (constitution XI
// 1.4.0). Text scales up to 1.15 (research R8). On short screens it is one
// 64 pt row: pause, then the strip with reputation as a line along its top
// edge, clear of the fares; the title moves to the pause card (M07
// contracts/compact-trip-layout.md "TripHud, compact").
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/theme/components/buttons.dart';
import 'package:wassal/core/theme/components/pills.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/trip/domain/scene_layout.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';
import 'package:wassal/features/trip/presentation/top_bar/station_strip_bar.dart';
import 'package:wassal/features/trip/presentation/trip_motion.dart';
import 'package:wassal/features/trip/presentation/trip_scope.dart';
import 'package:wassal/features/trip/presentation/trip_text.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

/// The HUD's first row: pause, title, reputation.
const hudRowHeight = 44.0;

class TripHud extends StatelessWidget {
  const TripHud({
    required this.onPause,
    this.onDebug,
    this.compact = false,
    super.key,
  });

  final VoidCallback onPause;

  /// Opens the debug panel; null on prod (M02 research R21).
  final VoidCallback? onDebug;

  /// The short screens' HUD.
  final bool compact;

  static const pauseKey = ValueKey('trip-pause');
  static const debugKey = ValueKey('trip-debug');
  static const titleKey = ValueKey('trip-hud-title');
  static const reputationLineKey = ValueKey('trip-hud-reputation-line');
  static const reputationLowKey = ValueKey('trip-hud-reputation-low');

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final buttons = [
      IconCircleButton(
        key: pauseKey,
        icon: 'pause',
        semanticLabel: l10n.tripTopBarPause,
        onTap: onPause,
      ),
      if (onDebug case final onDebug?) ...[
        const SizedBox(width: SpaceTokens.s8),
        IconCircleButton(
          key: debugKey,
          icon: 'tasks',
          semanticLabel: l10n.tripDebugOpen,
          onTap: onDebug,
        ),
      ],
    ];
    if (compact) {
      return TripTextScale.scope(
        context,
        child: SizedBox(
          height: compactHudHeight,
          child: Padding(
            // Room above the card for the reputation line and its chip,
            // which sit on its top edge; none under it.
            padding: const EdgeInsets.only(
              left: SpaceTokens.s16,
              right: SpaceTokens.s16,
              top: compactHudHeight - stripHeight,
            ),
            child: Row(
              children: [
                ...buttons,
                const SizedBox(width: SpaceTokens.s8),
                const Expanded(child: _StripWithReputation()),
              ],
            ),
          ),
        ),
      );
    }
    return TripTextScale.scope(
      context,
      child: SizedBox(
        height: tripHudHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: SpaceTokens.s16),
          child: Column(
            children: [
              SizedBox(
                height: hudRowHeight,
                child: Row(
                  children: [
                    ...buttons,
                    const SizedBox(width: SpaceTokens.s10),
                    const Expanded(child: TripTitle()),
                    const SizedBox(width: SpaceTokens.s10),
                    const ReputationBar(),
                  ],
                ),
              ),
              const SizedBox(height: SpaceTokens.s6),
              const StationStrip(),
            ],
          ),
        ),
      ),
    );
  }
}

/// The compact HUD's strip: reputation a 6 pt line centred on the card's top
/// edge, over the track's length, `primary`, `danger` under 40% with
/// «تحت ٤٠٪» on the line's end. The card's bottom holds the fares.
class _StripWithReputation extends ConsumerWidget {
  const _StripWithReputation();

  static const double _line = 6;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final numbers = ref.watch(numberFormatterProvider);
    final l10n = AppLocalizations.of(context);
    return TripSelector<TopBarView?>(
      select: (model) => model.view?.topBar,
      builder: (context, bar) {
        final reputation = bar?.reputation ?? 100;
        final low = bar?.reputationLow ?? false;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            const StationStrip(compact: true),
            PositionedDirectional(
              start: SpaceTokens.s14 * 2,
              end: SpaceTokens.s14 * 2,
              top: -_line / 2,
              height: _line,
              child: Semantics(
                label: l10n.tripTopBarReputation(
                  numbers.integer(reputation),
                  numbers.integer(100),
                ),
                excludeSemantics: true,
                child: _ReputationFill(
                  key: TripHud.reputationLineKey,
                  share: reputation / 100,
                  low: low,
                ),
              ),
            ),
            if (low)
              const PositionedDirectional(
                end: SpaceTokens.s10,
                top: 0,
                child: FractionalTranslation(
                  translation: Offset(0, -0.5),
                  child: ExcludeSemantics(
                    child: _LowChip(key: TripHud.reputationLowKey),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// A pill track on `track`, filled to [share] in `primary`, or `danger`
/// when [low].
class _ReputationFill extends StatelessWidget {
  const _ReputationFill({required this.share, required this.low, super.key});

  final double share;
  final bool low;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      color: ColorTokens.track,
      borderRadius: BorderRadius.all(Radius.circular(RadiusTokens.pill)),
    ),
    child: Align(
      alignment: AlignmentDirectional.centerStart,
      child: FractionallySizedBox(
        widthFactor: share.clamp(0.0, 1.0),
        heightFactor: 1,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: low ? ColorTokens.danger : ColorTokens.primary,
            borderRadius: const BorderRadius.all(
              Radius.circular(RadiusTokens.pill),
            ),
          ),
        ),
      ),
    ),
  );
}

/// «تحت ٤٠٪» on `danger.soft`.
class _LowChip extends ConsumerWidget {
  const _LowChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final numbers = ref.watch(numberFormatterProvider);
    final l10n = AppLocalizations.of(context);
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: ColorTokens.dangerSoft,
        borderRadius: BorderRadius.all(Radius.circular(RadiusTokens.pill)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: SpaceTokens.s6),
        child: Text(
          l10n.tripReputationLow(
            numbers.integer(TripMotion.reputationLowPercent),
          ),
          style: TypeTokens.label.weight(700).copyWith(color: ColorTokens.ink),
        ),
      ),
    );
  }
}

/// The line and trip; on a story trip, «مشوار قصة» above it, and, when the
/// chapter has `story_trip_info`, its title in the line and number's place
/// (specs/015-m10-apartment-story). In the HUD, and in the compact profile's
/// pause card ([alignment] centre).
class TripTitle extends ConsumerWidget {
  const TripTitle({
    this.alignment = AlignmentDirectional.centerStart,
    super.key,
  });

  final AlignmentDirectional alignment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final numbers = ref.watch(numberFormatterProvider);
    final l10n = AppLocalizations.of(context);
    return TripSelector<(TopBarView?, bool)>(
      select: (model) => (model.view?.topBar, model.view?.storyStrip != null),
      builder: (context, shown) {
        final (bar, hasStrip) = shown;
        if (bar == null) return const SizedBox.shrink();
        final story = hasStrip || bar.storyTitle != null;
        final number = numbers.integer(bar.tripNumber);
        // Whole, on one line: where the debug button narrows the row
        // (internal builds), it shrinks rather than cut.
        final title = FittedBox(
          fit: BoxFit.scaleDown,
          alignment: alignment,
          child: Text(
            switch ((bar.storyTitle, bar.lineName)) {
              // A story trip's own title (M10), else M02's line and number.
              (final storyTitle?, _) => storyTitle,
              (_, final line?) => l10n.tripHudTitle(line, number),
              _ => l10n.tripTopBarTrip(number),
            },
            key: TripHud.titleKey,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DesignExtras.hudTitle.copyWith(color: ColorTokens.ink),
          ),
        );
        if (!story) return Align(alignment: alignment, child: title);
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: alignment == AlignmentDirectional.center
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
          children: [
            StatusChip.story(label: l10n.tripStoryChip),
            title,
          ],
        );
      },
    );
  }
}

/// «السمعة» over a 92×12 bar, `primary`; under 40% `danger`, with
/// «تحت ٤٠٪» beside the label.
class ReputationBar extends ConsumerWidget {
  const ReputationBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final numbers = ref.watch(numberFormatterProvider);
    final l10n = AppLocalizations.of(context);
    return TripSelector<TopBarView?>(
      select: (model) => model.view?.topBar,
      builder: (context, bar) {
        final reputation = bar?.reputation ?? 100;
        final low = bar?.reputationLow ?? false;
        final color = low ? ColorTokens.danger : ColorTokens.primary;
        final label = TypeTokens.label.copyWith(color: ColorTokens.ink);
        return Semantics(
          label: l10n.tripTopBarReputation(
            numbers.integer(reputation),
            numbers.integer(100),
          ),
          excludeSemantics: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(l10n.tripReputationLabel, style: label),
                  if (low) ...[
                    const SizedBox(width: SpaceTokens.s4),
                    DecoratedBox(
                      decoration: const BoxDecoration(
                        color: ColorTokens.dangerSoft,
                        borderRadius: BorderRadius.all(
                          Radius.circular(RadiusTokens.pill),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: SpaceTokens.s4,
                        ),
                        child: Text(
                          l10n.tripReputationLow(
                            numbers.integer(TripMotion.reputationLowPercent),
                          ),
                          style: label.weight(700),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: SpaceTokens.s4),
              SizedBox.fromSize(
                size: DesignExtras.reputationBar,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: ColorTokens.paper,
                    borderRadius: const BorderRadius.all(
                      Radius.circular(RadiusTokens.pill),
                    ),
                    border: Border.all(
                      color: ColorTokens.outline,
                      width: 2,
                      strokeAlign: BorderSide.strokeAlignInside,
                    ),
                  ),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: FractionallySizedBox(
                      widthFactor: (reputation / 100).clamp(0.0, 1.0),
                      heightFactor: 1,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: const BorderRadius.all(
                            Radius.circular(RadiusTokens.pill),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
