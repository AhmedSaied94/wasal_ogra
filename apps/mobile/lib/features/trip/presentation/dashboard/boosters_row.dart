// The boosters (HANDOFF §3.4 `BoosterButton`, `C-Trip` boxes 81–92): four
// buttons on `dashboard.raised`, each its icon over its name, with a badge
// at its top end: how many are left in `sun`, the price «N بون» in
// `primary` when none is, or the seconds left while one is working. The ad
// badge waits for the ads feature (M11, spec FR-029). A tap uses one or
// opens its purchase card.
import 'package:content_models/content_models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/theme/components/app_icon.dart';
import 'package:wassal/core/theme/components/pressable.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';
import 'package:wassal/features/trip/domain/wire.dart';
import 'package:wassal/features/trip/presentation/dashboard/tray.dart';
import 'package:wassal/features/trip/presentation/trip_scope.dart';
import 'package:wassal/features/trip/presentation/trip_text.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

/// A booster and, while it works, its whole seconds left.
typedef _Slot = (BoosterSlotView, int?);

class BoostersRow extends StatelessWidget {
  const BoostersRow({super.key});

  static Key slotKey(BoosterId booster) =>
      ValueKey('trip-booster-${wireOf(booster)}');

  @override
  Widget build(BuildContext context) {
    return TripSelector<List<_Slot>>(
      select: (model) {
        final view = model.view;
        if (view == null) return const [];
        return [
          for (final slot in view.boosters)
            (
              slot,
              switch (slot.activeUntilMs) {
                final until? when until > view.tMs =>
                  ((until - view.tMs) / 1000).ceil(),
                _ => null,
              },
            ),
        ];
      },
      equals: listEquals,
      builder: (context, slots) {
        if (slots.isEmpty) return const SizedBox.shrink();
        return Row(
          children: [
            for (final (i, (slot, secondsLeft)) in slots.indexed) ...[
              if (i > 0) const SizedBox(width: traySlotGap),
              Expanded(
                child: BoosterButton(slot: slot, secondsLeft: secondsLeft),
              ),
            ],
          ],
        );
      },
    );
  }
}

class BoosterButton extends ConsumerWidget {
  const BoosterButton({required this.slot, this.secondsLeft, super.key});

  final BoosterSlotView slot;

  /// Shown in the badge while the booster works.
  final int? secondsLeft;

  static const _corners = BorderRadius.all(Radius.circular(RadiusTokens.tray));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final numbers = ref.watch(numberFormatterProvider);
    final l10n = AppLocalizations.of(context);
    final controls = TripScope.of(context).controls;
    final booster = slot.booster;
    final name = l10n.boosterName(
      booster,
      jamSeconds: jamSecondsOf(context, numbers),
    );
    final price = slot.priceBonat;
    final forSale = slot.count == 0 && price != null;
    final active = secondsLeft;
    final label = active != null
        ? l10n.tripBoosterActive(name, active, numbers.integer(active))
        : !slot.enabled
        ? l10n.tripBoosterUnavailable(name)
        : forSale
        ? l10n.tripBoosterForSale(name, price, numbers.integer(price))
        : l10n.tripBoosterCount(name, numbers.integer(slot.count));
    final badge = switch (secondsLeft) {
      final s? => BoosterBadge(
        text: l10n.tripSeconds(numbers.integer(s)),
        color: ColorTokens.sun,
        textColor: ColorTokens.ink,
      ),
      null when forSale => BoosterBadge(
        text: l10n.tripBoosterPriceBadge(numbers.integer(price)),
        color: ColorTokens.primary,
        textColor: ColorTokens.paper,
      ),
      null => BoosterBadge(
        text: l10n.tripTimes(numbers.integer(slot.count)),
        color: ColorTokens.sun,
        textColor: ColorTokens.ink,
      ),
    };
    return Shakeable(
      controlKey: TripControls.boosterKey(booster),
      child: KeyedSubtree(
        key: BoostersRow.slotKey(booster),
        child: Pressable(
          onTap: () => controls.useBooster(booster),
          haptic: false,
          enabled: slot.enabled,
          semanticLabel: label,
          toggled: active == null ? null : true,
          borderRadius: _corners,
          child: SizedBox(
            height: LayoutTokens.touchMin,
            child: Stack(
              clipBehavior: Clip.none,
              fit: StackFit.expand,
              children: [
                // At work (`TripEvents` block 9): `primary` with a 2 pt
                // `sun` ring inside.
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: active == null
                        ? ColorTokens.dashboardRaised
                        : ColorTokens.primary,
                    borderRadius: _corners,
                    border: active == null
                        ? null
                        : Border.all(
                            color: ColorTokens.sun,
                            width: DesignExtras.boosterActiveRing,
                            strokeAlign: BorderSide.strokeAlignInside,
                          ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    spacing: 1,
                    children: [
                      AppIcon(
                        icons[booster] ?? 'booster_traffic',
                        size: 18,
                        color: ColorTokens.paper,
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: SpaceTokens.s2,
                        ),
                        child: Text(
                          name,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.fade,
                          style: TypeTokens.label
                              .weight(600)
                              .copyWith(color: ColorTokens.paper, height: 1.2),
                        ),
                      ),
                    ],
                  ),
                ),
                PositionedDirectional(
                  top: -9,
                  end: -SpaceTokens.s4,
                  child: badge,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Each booster's icon.
  static const icons = {
    BoosterId.changeBag: 'booster_change_bag',
    BoosterId.ledgerPeek: 'booster_ledger',
    BoosterId.wakeAll: 'booster_wake',
    BoosterId.trafficJam: 'booster_traffic',
  };
}

/// A booster's pill at its top end: its count, price or seconds left.
class BoosterBadge extends StatelessWidget {
  const BoosterBadge({
    required this.text,
    required this.color,
    required this.textColor,
    super.key,
  });

  final String text;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: const BorderRadius.all(
          Radius.circular(RadiusTokens.pill),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: SpaceTokens.s6 + 1),
        child: Text(
          text,
          maxLines: 1,
          softWrap: false,
          style: TypeTokens.label
              .weight(700)
              .copyWith(color: textColor, height: 1.5),
        ),
      ),
    );
  }
}
