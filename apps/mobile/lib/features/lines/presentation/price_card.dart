// The price against the jenehat (specs/014-m09-lines-vehicles, HANDOFF
// `BuyVehicle` block 2e), read as one node: «السعر {price} جنيه، معاك
// {jenehat} جنيه».
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/theme/components/app_icon.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

class PriceCard extends ConsumerWidget {
  const PriceCard({required this.price, required this.jenehat, super.key});

  final int price;
  final int jenehat;

  static const double _firstRow = 44;
  static const double _secondRow = 40;
  static const double _coin = 22;
  static const double _divider = 2;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final numbers = ref.watch(numberFormatterProvider);
    final label = DesignExtras.buyVehiclePriceLabel.copyWith(
      color: ColorTokens.inkMuted,
    );
    return Semantics(
      container: true,
      label: l10n.buyVehiclePriceA11y(
        numbers.integer(price),
        numbers.integer(jenehat),
      ),
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: SpaceTokens.s14,
            vertical: SpaceTokens.s4,
          ),
          decoration: BoxDecoration(
            color: ColorTokens.paper,
            borderRadius: BorderRadius.circular(RadiusTokens.bubble),
            border: Border.all(
              color: ColorTokens.track,
              width: _divider,
              strokeAlign: BorderSide.strokeAlignInside,
            ),
          ),
          child: Column(
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: _firstRow),
                child: Row(
                  children: [
                    Expanded(child: Text(l10n.buyVehiclePrice, style: label)),
                    const AppIcon('coin', size: _coin),
                    const SizedBox(width: SpaceTokens.s4),
                    Text(
                      numbers.integer(price),
                      style: DesignExtras.buyVehiclePrice.copyWith(
                        color: ColorTokens.ink,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(
                height: _divider,
                width: double.infinity,
                child: ColoredBox(color: ColorTokens.track),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: _secondRow),
                child: Row(
                  children: [
                    Expanded(child: Text(l10n.buyVehicleHave, style: label)),
                    Text(
                      l10n.buyVehicleBalance(numbers.integer(jenehat)),
                      style: DesignExtras.buyVehicleBalance.copyWith(
                        color: ColorTokens.ink,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
