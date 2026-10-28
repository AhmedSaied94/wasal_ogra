// Home's start button (specs/013-m08-home-result, contracts/home.md
// "States", research R11, HANDOFF `C-Home` block 4, `HomeStates` block 5):
// «يلا نطلع!» with its liter, without it during an unlimited window, and
// «البنزين خلص» with the next liter's countdown on an empty tank. The
// economy's view decides which; the variants cross-fade.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/routing/nav_guard.dart';
import 'package:wassal/core/theme/components/app_icon.dart';
import 'package:wassal/core/theme/components/buttons.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/home/application/home_model.dart';
import 'package:wassal/features/home/application/start_next_trip.dart';
import 'package:wassal/features/home/presentation/trusted_countdown.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

/// What a start costs, in liters (the product's rule).
const litersPerStart = 1;

class HomeStartButton extends ConsumerWidget {
  const HomeStartButton({required this.model, super.key});

  final HomeModel model;

  static const startKey = Key('HomeStartButton.start');
  static const emptyKey = Key('HomeStartButton.empty');

  static const double _timerIcon = 16;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final numbers = ref.watch(numberFormatterProvider);
    final next = model.next;
    final Widget button = switch (model.fuelState) {
      HomeFuelState.empty => AppButton.danger(
        key: emptyKey,
        label: l10n.homeCtaOutOfFuel,
        semanticLabel: l10n.homeA11yOutOfFuel,
        trailing: switch (model.fuel.nextLiterAtMs) {
          final until? => _NextLiterChip(untilMs: until),
          null => null,
        },
        onTap: () => NavGuard.go(context, fuelSheetLocation),
      ),
      final state => AppButton.primary(
        key: startKey,
        label: l10n.homeCtaStart,
        enabled: next != null,
        semanticLabel: switch ((next, state)) {
          (null, _) => l10n.homeA11yNoTrip,
          (_, HomeFuelState.unlimited) => l10n.homeCtaStart,
          _ => l10n.homeA11yStart,
        },
        trailing: state == HomeFuelState.unlimited
            ? null
            : CostChip(
                amount: l10n.homeFuelCost(numbers.integer(litersPerStart)),
                large: true,
              ),
        onTap: next == null
            ? null
            : () => unawaited(
                startNextTrip(
                  context,
                  ref,
                  tripId: next.tripId,
                  from: StartFrom.home,
                ),
              ),
      ),
    };
    return AnimatedSwitcher(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : DesignExtras.ctaSwap,
      child: button,
    );
  }
}

/// «اللتر الجاي {m:ss}» on `paper` with the timer glyph (`HomeStates`).
class _NextLiterChip extends StatelessWidget {
  const _NextLiterChip({required this.untilMs});

  final int untilMs;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: ColorTokens.paper,
        borderRadius: BorderRadius.circular(RadiusTokens.pill),
      ),
      child: SizedBox(
        height: DesignExtras.costChipHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: SpaceTokens.s10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: SpaceTokens.s4,
            children: [
              const AppIcon(
                'timer',
                size: HomeStartButton._timerIcon,
                color: ColorTokens.ink,
              ),
              TrustedCountdown(
                untilMs: untilMs,
                template: l10n.homeNextLiter,
                style: TypeTokens.caption
                    .weight(700)
                    .copyWith(color: ColorTokens.ink),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
