// The card's boosters (specs/013-m08-home-result, `PreTrip` boxes 43–57,
// FR-031): four tiles with their counts, not tappable, and the chip that
// offers the first one at 0. The whole block is hidden while M07 locks the
// boosters (FR-032).
import 'package:content_models/content_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/theme/components/app_icon.dart';
import 'package:wassal/core/theme/components/pressable.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/pre_trip/domain/briefing.dart';
import 'package:wassal/features/trip/presentation/dashboard/boosters_row.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

/// A booster's short name, as its tile shows it.
String boosterTileName(AppLocalizations l10n, BoosterId booster) =>
    switch (booster) {
      BoosterId.changeBag => l10n.tripBoosterChangeBag,
      BoosterId.ledgerPeek => l10n.tripBoosterLedgerPeek,
      BoosterId.wakeAll => l10n.tripBoosterWakeAll,
      _ => l10n.preTripBoosterJam,
    };

class BoosterTiles extends ConsumerWidget {
  const BoosterTiles({
    required this.tiles,
    required this.offer,
    required this.onBuy,
    super.key,
  });

  final List<BoosterTile> tiles;
  final BuyOffer? offer;
  final VoidCallback onBuy;

  static const buyKey = Key('BoosterTiles.buy');
  static Key tileKey(BoosterId booster) => ValueKey('BoosterTiles.$booster');

  static const double _tileHeight = 66;
  static const double _icon = 22;
  static const double _chipHeight = 44;
  static const double _plus = 16;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final numbers = ref.watch(numberFormatterProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: SpaceTokens.s6,
      children: [
        Text(
          l10n.preTripBoosters,
          style: DesignExtras.preTripLine.copyWith(color: ColorTokens.inkMuted),
        ),
        // A name that wraps makes every tile that much taller.
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: SpaceTokens.s8,
            children: [
              for (final tile in tiles)
                Expanded(
                  child: Semantics(
                    key: tileKey(tile.booster),
                    container: true,
                    label: l10n.tripBoosterCount(
                      boosterTileName(l10n, tile.booster),
                      numbers.integer(tile.count),
                    ),
                    excludeSemantics: true,
                    child: Container(
                      constraints: const BoxConstraints(minHeight: _tileHeight),
                      padding: const EdgeInsets.symmetric(
                        vertical: SpaceTokens.s4,
                        horizontal: SpaceTokens.s4,
                      ),
                      decoration: BoxDecoration(
                        color: ColorTokens.ground,
                        borderRadius: BorderRadius.circular(RadiusTokens.m),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AppIcon(
                            BoosterButton.icons[tile.booster] ??
                                'booster_traffic',
                            size: _icon,
                          ),
                          Text(
                            boosterTileName(l10n, tile.booster),
                            textAlign: TextAlign.center,
                            style: TypeTokens.label
                                .weight(600)
                                .copyWith(color: ColorTokens.ink),
                          ),
                          Text(
                            l10n.preTripBoosterCount(
                              numbers.integer(tile.count),
                            ),
                            style: TypeTokens.label
                                .weight(700)
                                .copyWith(color: ColorTokens.ink),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (offer case final offer?)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Pressable(
              key: buyKey,
              onTap: onBuy,
              borderRadius: BorderRadius.circular(RadiusTokens.pill),
              semanticLabel: l10n.preTripBuyChip(
                boosterTileName(l10n, offer.booster),
                offer.priceBonat,
                numbers.integer(offer.priceBonat),
              ),
              child: Container(
                constraints: const BoxConstraints(minHeight: _chipHeight),
                padding: const EdgeInsets.symmetric(
                  horizontal: SpaceTokens.s14,
                ),
                decoration: BoxDecoration(
                  color: ColorTokens.primarySoft,
                  borderRadius: BorderRadius.circular(RadiusTokens.pill),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: SpaceTokens.s8,
                  children: [
                    const AppIcon(
                      'plus',
                      size: _plus,
                      color: ColorTokens.primary,
                    ),
                    Flexible(
                      child: Text(
                        l10n.preTripBuyChip(
                          boosterTileName(l10n, offer.booster),
                          offer.priceBonat,
                          numbers.integer(offer.priceBonat),
                        ),
                        style: TypeTokens.body
                            .weight(700)
                            .copyWith(color: ColorTokens.primary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
