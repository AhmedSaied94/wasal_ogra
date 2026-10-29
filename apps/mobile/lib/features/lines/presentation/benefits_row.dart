// What a vehicle brings (specs/014-m09-lines-vehicles, HANDOFF `BuyVehicle`
// block 2d): its seats against the current vehicle's, the line it opens
// (when it opens one), and more pay. Equal heights; labels wrap.
import 'package:content_models/content_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/content/content_providers.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/theme/components/app_icon.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/lines/domain/vehicle_offer.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

class BenefitsRow extends ConsumerWidget {
  const BenefitsRow({required this.offer, super.key});

  final VehicleOffer offer;

  static const double _icon = 26;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final numbers = ref.watch(numberFormatterProvider);
    final opens = switch (offer.opensLine) {
      final LineId line => ref.watch(contentSourceProvider).line(line),
      null => null,
    };
    final current = numbers.integer(offer.currentSeats);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: SpaceTokens.s8,
        children: [
          _Tile(
            semanticLabel: l10n.buyVehicleSeatsA11y(
              offer.seats,
              numbers.integer(offer.seats),
              current,
            ),
            top: Text(
              numbers.integer(offer.seats),
              style: DesignExtras.buyVehicleBenefitNumber.copyWith(
                color: ColorTokens.ink,
              ),
            ),
            label: l10n.buyVehicleSeats(offer.seats, current),
          ),
          if (opens != null)
            _Tile(
              top: const AppIcon(
                'route_bold',
                size: _icon,
                color: ColorTokens.primary,
              ),
              label: l10n.buyVehicleOpens(opens.name.arEg),
            ),
          _Tile(
            top: const AppIcon('coin_up', size: _icon, color: ColorTokens.gold),
            label: l10n.buyVehicleMorePay,
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.top, required this.label, this.semanticLabel});

  final Widget top;
  final String label;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Semantics(
      container: true,
      label: semanticLabel ?? label,
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: SpaceTokens.s8,
            vertical: SpaceTokens.s10,
          ),
          decoration: BoxDecoration(
            color: ColorTokens.ground,
            borderRadius: BorderRadius.circular(RadiusTokens.m),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: SpaceTokens.s4,
            children: [
              top,
              Text(
                label,
                textAlign: TextAlign.center,
                style: DesignExtras.buyVehicleBenefit.copyWith(
                  color: ColorTokens.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
