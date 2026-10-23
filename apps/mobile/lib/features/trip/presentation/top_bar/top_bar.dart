// The top bar (ux-spec «الشريط العلوي», FR-019): pause on the right, the
// line and the trip's number in the middle, reputation on the left, and the
// station strip under them. Pause, and on internal builds the debug panel's
// icon beside it, are the only controls up here: both stop play
// (constitution XI 1.4.0).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/theme/app_theme.dart';
import 'package:wassal/core/theme/tokens/shape.dart';
import 'package:wassal/core/theme/tokens/space.dart';
import 'package:wassal/core/theme/tokens/typography.dart';
import 'package:wassal/features/trip/domain/scene_layout.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';
import 'package:wassal/features/trip/presentation/top_bar/station_strip_bar.dart';
import 'package:wassal/features/trip/presentation/trip_scope.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

/// The bar's first row: pause, names, reputation.
const topRowHeight = 52.0;

class TripTopBar extends StatelessWidget {
  const TripTopBar({required this.onPause, this.onDebug, super.key});

  final VoidCallback onPause;

  /// Opens the debug panel; null on prod (research R21).
  final VoidCallback? onDebug;

  static const pauseKey = ValueKey('trip-pause');
  static const debugKey = ValueKey('trip-debug');

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.shams,
        border: Border(
          bottom: BorderSide(color: tokens.hibr, width: ShapeTokens.borderCard),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
        child: SizedBox(
          height: topBarHeight - ShapeTokens.borderCard,
          child: Column(
            children: [
              SizedBox(
                height: topRowHeight,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: SpaceTokens.m,
                  ),
                  child: Row(
                    children: [
                      _RoundButton(
                        buttonKey: pauseKey,
                        icon: Icons.pause_rounded,
                        label: l10n.tripTopBarPause,
                        onPressed: onPause,
                      ),
                      if (onDebug case final onDebug?) ...[
                        const SizedBox(width: SpaceTokens.s),
                        _RoundButton(
                          buttonKey: debugKey,
                          icon: Icons.bug_report_rounded,
                          label: l10n.tripDebugOpen,
                          onPressed: onDebug,
                        ),
                      ],
                      const SizedBox(width: SpaceTokens.s),
                      const Expanded(child: _Names()),
                      const SizedBox(width: SpaceTokens.s),
                      const _Reputation(),
                    ],
                  ),
                ),
              ),
              const Expanded(child: StationStripBar()),
            ],
          ),
        ),
      ),
    );
  }
}

/// A white circle, 44 pt (ux-spec).
class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.buttonKey,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final Key buttonKey;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        key: buttonKey,
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: SizedBox.square(
          dimension: ShapeTokens.minTouch,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: tokens.waraq,
              shape: BoxShape.circle,
              border: Border.all(
                color: tokens.hibr,
                width: ShapeTokens.borderCard,
              ),
              boxShadow: [
                BoxShadow(
                  color: tokens.hibr,
                  offset: hardShadowOffset(2, Directionality.of(context)),
                ),
              ],
            ),
            child: Icon(icon, color: tokens.hibr),
          ),
        ),
      ),
    );
  }
}

class _Names extends ConsumerWidget {
  const _Names();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final numbers = ref.watch(numberFormatterProvider);
    final l10n = AppLocalizations.of(context);
    return TripSelector<TopBarView?>(
      select: (model) => model.view?.topBar,
      builder: (context, bar) {
        if (bar == null) return const SizedBox.shrink();
        final line = bar.lineName;
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (line != null)
              Text(
                line,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TypeTokens.label.copyWith(
                  color: tokens.hibr,
                  height: 1.2,
                ),
              ),
            Text(
              l10n.tripTopBarTrip(numbers.integer(bar.tripNumber)),
              maxLines: 1,
              style: TypeTokens.caption.copyWith(
                color: tokens.hibr,
                height: 1.2,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Blue, orange below 40%.
class _Reputation extends ConsumerWidget {
  const _Reputation();

  static const _width = 76.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final numbers = ref.watch(numberFormatterProvider);
    final l10n = AppLocalizations.of(context);
    return TripSelector<TopBarView?>(
      select: (model) => model.view?.topBar,
      builder: (context, bar) {
        final reputation = bar?.reputation ?? 100;
        final low = bar?.reputationLow ?? false;
        return Semantics(
          label: l10n.tripTopBarReputation(
            numbers.integer(reputation),
            numbers.integer(100),
          ),
          excludeSemantics: true,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.favorite_rounded,
                color: low ? tokens.danger : tokens.primary,
                size: 20,
              ),
              const SizedBox(width: SpaceTokens.xs),
              Container(
                width: _width,
                height: 14,
                decoration: BoxDecoration(
                  color: tokens.waraq,
                  border: Border.all(color: tokens.hibr, width: 2),
                  borderRadius: BorderRadius.circular(
                    ShapeTokens.radiusControl,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                alignment: AlignmentDirectional.centerEnd,
                child: FractionallySizedBox(
                  widthFactor: (reputation / 100).clamp(0.0, 1.0),
                  child: ColoredBox(
                    color: low ? tokens.danger : tokens.primary,
                    child: const SizedBox.expand(),
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
