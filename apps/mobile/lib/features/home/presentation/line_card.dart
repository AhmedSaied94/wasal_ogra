// Home's line card (specs/013-m08-home-result, HANDOFF `C-Home` block 3):
// the next trip's line, its place in the line, the trips finished as a bar
// and the stars earned. Opens the lines.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/routing/nav_guard.dart';
import 'package:wassal/core/theme/components/app_icon.dart';
import 'package:wassal/core/theme/components/containers.dart';
import 'package:wassal/core/theme/components/pressable.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/home/domain/line_card.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

class HomeLineCard extends ConsumerWidget {
  const HomeLineCard({required this.figures, super.key});

  final LineCardFigures figures;

  static const double height = 70;
  static const double _tile = 44;
  static const double _tileIcon = 24;
  static const double _star = 24;
  static const double _rowGap = 5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final numbers = ref.watch(numberFormatterProvider);
    final f = figures;
    final radius = BorderRadius.circular(RadiusTokens.card);
    return Pressable(
      onTap: () => NavGuard.go(context, '/lines'),
      lip: LipTokens.card,
      borderRadius: radius,
      semanticLabel: l10n.homeA11yLine(
        f.lineName,
        numbers.integer(f.tripIndex),
        numbers.integer(f.tripTotal),
        numbers.integer(f.starsEarned),
        numbers.integer(f.starsMax),
      ),
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
                color: ColorTokens.primarySoft,
                borderRadius: BorderRadius.circular(RadiusTokens.tray),
              ),
              alignment: Alignment.center,
              child: const AppIcon(
                'route_bold',
                size: _tileIcon,
                color: ColorTokens.primary,
              ),
            ),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: _rowGap,
                children: [
                  // On one baseline as drawn; the trip's place goes under
                  // the name when both don't fit.
                  Wrap(
                    spacing: SpaceTokens.s8,
                    crossAxisAlignment: WrapCrossAlignment.end,
                    children: [
                      Text(
                        f.lineName,
                        style: TypeTokens.displayS.copyWith(
                          color: ColorTokens.ink,
                        ),
                      ),
                      Text(
                        l10n.homeLineTripOf(
                          numbers.integer(f.tripIndex),
                          numbers.integer(f.tripTotal),
                        ),
                        style: TypeTokens.caption.copyWith(
                          color: ColorTokens.inkMuted,
                        ),
                      ),
                    ],
                  ),
                  ProgressBar(value: f.progress),
                ],
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              spacing: SpaceTokens.s2,
              children: [
                const AppIcon('star', size: _star, color: ColorTokens.gold),
                Text(
                  numbers.ratio(f.starsEarned, f.starsMax),
                  style: DesignExtras.pillNumber.copyWith(
                    color: ColorTokens.ink,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
