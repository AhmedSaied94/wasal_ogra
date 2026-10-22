// The boosters (ux-spec «التابلوه» row 4): كيس فكة، صحّي النايم، الدفتر،
// زحمة, two by two beside the drawer. Each shows how many are left, or its
// price in BONAT when none is; a tap uses one or opens its purchase card.
import 'package:content_models/content_models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/theme/app_theme.dart';
import 'package:wassal/core/theme/tokens/shape.dart';
import 'package:wassal/core/theme/tokens/space.dart';
import 'package:wassal/core/theme/tokens/typography.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';
import 'package:wassal/features/trip/presentation/dashboard/tray.dart';
import 'package:wassal/features/trip/presentation/trip_scope.dart';
import 'package:wassal/features/trip/presentation/trip_text.dart';
import 'package:wassal/features/trip/domain/wire.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

class BoostersRow extends StatelessWidget {
  const BoostersRow({super.key});

  static Key slotKey(BoosterId booster) =>
      ValueKey('trip-booster-${wireOf(booster)}');

  @override
  Widget build(BuildContext context) {
    return TripSelector<List<BoosterSlotView>>(
      select: (model) => model.view?.boosters ?? const [],
      equals: listEquals,
      builder: (context, slots) {
        if (slots.isEmpty) return const SizedBox.shrink();
        final rows = [slots.take(2).toList(), slots.skip(2).toList()];
        return Column(
          children: [
            for (final (i, row) in rows.indexed) ...[
              if (i > 0) const SizedBox(height: traySlotGap),
              Expanded(
                child: Row(
                  children: [
                    for (final (j, slot) in row.indexed) ...[
                      if (j > 0) const SizedBox(width: traySlotGap),
                      Expanded(child: BoosterSlot(slot: slot)),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class BoosterSlot extends ConsumerWidget {
  const BoosterSlot({required this.slot, super.key});

  final BoosterSlotView slot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final numbers = ref.watch(numberFormatterProvider);
    final l10n = AppLocalizations.of(context);
    final controls = TripScope.of(context).controls;
    final booster = slot.booster;
    final name = l10n.boosterName(booster);
    final price = slot.priceBonat;
    final forSale = slot.count == 0 && price != null;
    final label = !slot.enabled
        ? l10n.tripBoosterUnavailable(name)
        : forSale
        ? l10n.tripBoosterForSale(name, numbers.integer(price))
        : l10n.tripBoosterCount(name, numbers.integer(slot.count));
    final caption = TypeTokens.caption.copyWith(
      color: tokens.hibr,
      fontWeight: FontWeight.w700,
      fontVariations: const [FontVariation('wght', 700)],
      height: 1.1,
    );
    return Shakeable(
      controlKey: TripControls.boosterKey(booster),
      child: Semantics(
        button: true,
        enabled: slot.enabled,
        label: label,
        excludeSemantics: true,
        child: GestureDetector(
          key: BoostersRow.slotKey(booster),
          behavior: HitTestBehavior.opaque,
          onTap: slot.enabled ? () => controls.useBooster(booster) : null,
          child: Opacity(
            opacity: slot.enabled ? 1 : 0.45,
            child: Container(
              constraints: const BoxConstraints(
                minHeight: ShapeTokens.minTouch,
                minWidth: ShapeTokens.minTouch,
              ),
              decoration: BoxDecoration(
                color: tokens.waraq,
                border: Border.all(
                  color: tokens.hibr,
                  width: ShapeTokens.borderCard,
                ),
                borderRadius: BorderRadius.circular(ShapeTokens.radiusControl),
              ),
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(boosterIcon(booster), size: 20, color: tokens.hibr),
                      if (forSale)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(numbers.integer(price), style: caption),
                            const SizedBox(width: 2),
                            Icon(
                              Icons.diamond_rounded,
                              size: 12,
                              color: tokens.primary,
                            ),
                          ],
                        ),
                    ],
                  ),
                  if (!forSale)
                    PositionedDirectional(
                      top: -SpaceTokens.s,
                      end: -SpaceTokens.s,
                      child: CountBadge(count: numbers.integer(slot.count)),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A booster's picture until the art arrives.
IconData boosterIcon(BoosterId booster) => switch (booster) {
  BoosterId.changeBag => Icons.savings_rounded,
  BoosterId.wakeAll => Icons.alarm_rounded,
  BoosterId.ledgerPeek => Icons.menu_book_rounded,
  _ => Icons.traffic_rounded,
};
