// The start refused for an empty tank (M11's `NoFuelAd`): the fuel tile
// and title, when the next free liter comes on trusted time in a pill, the
// refill ad beside the BONAT refill (`FuelRefillAdOffer`), and the way to
// the fuel sheet or back to the stand as two 48-high tiles.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/economy/economy_providers.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/theme/components/app_icon.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/fuel/presentation/fuel_refill_ad_offer.dart';
import 'package:wassal/features/trip/presentation/cards/trip_card.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

class NoFuelCard extends ConsumerStatefulWidget {
  const NoFuelCard({
    required this.nextLiterAtMs,
    required this.onFuel,
    required this.onHome,
    this.onFilled,
    super.key,
  });

  final int? nextLiterAtMs;
  final VoidCallback onFuel;
  final VoidCallback onHome;

  /// The tank was filled here; null draws no refill offer.
  final VoidCallback? onFilled;

  static const fuelKey = ValueKey('trip-no-fuel-shop');
  static const homeKey = ValueKey('trip-no-fuel-home');

  @override
  ConsumerState<NoFuelCard> createState() => _NoFuelCardState();
}

class _NoFuelCardState extends ConsumerState<NoFuelCard> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    if (widget.nextLiterAtMs != null) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final numbers = ref.watch(numberFormatterProvider);
    final next = widget.nextLiterAtMs;
    final now = ref.watch(trustedClockProvider).value?.nowMs();
    return TripCard(
      title: l10n.tripNoFuelTitle,
      titleStyle: DesignExtras.adCardTitle,
      designTop: DesignExtras.noFuelTop,
      padding: DesignExtras.adCardPadding,
      art: const CardArtTile(
        fill: ColorTokens.dangerSoft,
        child: AppIcon('fuel', size: DesignExtras.adCardTileArt),
      ),
      underTitle: next != null && now != null
          ? _NextLiterPill(
              l10n.tripNoFuelNext(
                numbers.countdown(Duration(milliseconds: next - now)),
              ),
            )
          : null,
      children: [
        if (widget.onFilled case final onFilled?)
          Padding(
            padding: const EdgeInsets.only(bottom: DesignExtras.adCardLowerGap),
            child: FuelRefillAdOffer(onFilled: onFilled),
          ),
        CardRow(
          children: [
            CardTile(
              key: NoFuelCard.fuelKey,
              label: l10n.tripNoFuelShop,
              height: DesignExtras.noFuelLinkHeight,
              radius: DesignExtras.noFuelLinkRadius,
              onTap: widget.onFuel,
            ),
            CardTile(
              key: NoFuelCard.homeKey,
              label: l10n.tripNoFuelHome,
              height: DesignExtras.noFuelLinkHeight,
              radius: DesignExtras.noFuelLinkRadius,
              onTap: widget.onHome,
            ),
          ],
        ),
      ],
    );
  }
}

/// `NoFuelAd` box 11: the timer and «اللتر الجاي …» in a `ground` pill.
class _NextLiterPill extends StatelessWidget {
  const _NextLiterPill(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    height: DesignExtras.noFuelPill,
    padding: const EdgeInsets.symmetric(horizontal: SpaceTokens.s12),
    decoration: BoxDecoration(
      color: ColorTokens.ground,
      borderRadius: BorderRadius.circular(RadiusTokens.pill),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      spacing: SpaceTokens.s4,
      children: [
        const AppIcon(
          'timer',
          size: DesignExtras.noFuelPillIcon,
          color: ColorTokens.ink,
        ),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DesignExtras.noFuelPillLabel.copyWith(
              color: ColorTokens.ink,
            ),
          ),
        ),
      ],
    ),
  );
}
