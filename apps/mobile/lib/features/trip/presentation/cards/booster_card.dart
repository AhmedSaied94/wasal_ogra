// A booster the player has none of (contracts/trip-controller.md "Booster
// purchase"; 008.5 `States` spend confirmation): its icon and name, its
// price in BONAT and the player's balance, «اشتري واستعمل», or «ناقصك …»
// when short, and «مش دلوقتي». For «زحمة», the ad «زحمة ببلاش» sits above
// the purchase when the ads layer shows it (M11, `BoosterAdCard`). The clock
// waits. A save that failed says so here, and buying again sends the same
// request.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/theme/components/app_icon.dart';
import 'package:wassal/core/theme/components/buttons.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/apartment/presentation/price_chip.dart';
import 'package:wassal/features/trip/application/trip_phase.dart';
import 'package:wassal/features/trip/domain/ad_slot.dart';
import 'package:wassal/features/trip/presentation/cards/trip_card.dart';
import 'package:wassal/features/trip/presentation/dashboard/boosters_row.dart';
import 'package:wassal/features/trip/presentation/trip_scope.dart';
import 'package:wassal/features/trip/presentation/trip_text.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

class BoosterCard extends ConsumerWidget {
  const BoosterCard({
    required this.card,
    required this.retry,
    required this.onBuy,
    required this.onClose,
    this.onWatchAd,
    super.key,
  });

  final BoosterCardModel card;

  /// A purchase that failed to save, or null.
  final TripRetry? retry;
  final VoidCallback onBuy;
  final VoidCallback onClose;

  /// The ad «زحمة»; null draws it disabled.
  final VoidCallback? onWatchAd;

  static const adKey = ValueKey('trip-booster-ad');
  static const buyKey = ValueKey('trip-booster-buy');
  static const closeKey = ValueKey('trip-booster-close');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (card.ad.shown) return _withAd(context, ref);
    final l10n = AppLocalizations.of(context);
    final numbers = ref.watch(numberFormatterProvider);
    final price = card.priceBonat;
    final short = card.shortBy;
    return TripCard(
      title: l10n.boosterName(
        card.booster,
        jamSeconds: jamSecondsOf(context, numbers),
      ),
      art: AppIcon(
        BoosterButton.icons[card.booster] ?? 'booster_traffic',
        size: DesignExtras.confirmArt,
      ),
      children: [
        if (price != null)
          CardText(l10n.tripBoosterCardPrice(numbers.integer(price))),
        CardText(
          l10n.tripBoosterCardBalance(card.bonat, numbers.integer(card.bonat)),
        ),
        if (short != null)
          CardText(l10n.tripBoosterShort(short, numbers.integer(short))),
        if (retry case final retry?) CardText(l10n.retryMessage(retry)),
        CardActions(
          confirm: short == null
              ? CardConfirm(
                  key: buyKey,
                  label: l10n.tripBoosterBuy,
                  onTap: onBuy,
                )
              : null,
          dismiss: CardTile(
            key: closeKey,
            label: l10n.tripBoosterClose,
            onTap: onClose,
          ),
        ),
      ],
    );
  }

  /// `BoosterAdCard`: the ad above the purchase, each full width and 66
  /// high, the price in a chip on the buy button, the balance under it,
  /// and «مش دلوقتي» last as a text button.
  Widget _withAd(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final numbers = ref.watch(numberFormatterProvider);
    final price = card.priceBonat;
    final short = card.shortBy;
    final priceBadge = price == null
        ? null
        : l10n.tripBoosterPriceBadge(numbers.integer(price));
    return TripCard(
      title: l10n.boosterName(
        card.booster,
        jamSeconds: jamSecondsOf(context, numbers),
      ),
      titleStyle: DesignExtras.adCardTitle,
      designTop: DesignExtras.boosterAdTop,
      padding: DesignExtras.boosterAdPadding,
      art: CardArtTile(
        fill: ColorTokens.dashboardRaised,
        child: AppIcon(
          BoosterButton.icons[card.booster] ?? 'booster_traffic',
          size: DesignExtras.boosterAdTileArt,
        ),
      ),
      children: [
        RewardedAdButton(
          key: adKey,
          ready: card.ad == AdSlot.ready && onWatchAd != null,
          title: l10n.trafficJamAdTitle,
          benefit: l10n.trafficJamAdBenefit(jamSecondsOf(context, numbers)),
          unavailable: card.ad == AdSlot.offline ? l10n.adNeedsNetwork : null,
          onTap: onWatchAd ?? () {},
        ),
        Padding(
          padding: const EdgeInsets.only(top: DesignExtras.adCardLowerGap),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: SpaceTokens.s12,
            children: [
              if (short == null)
                AppButton.primary(
                  key: buyKey,
                  label: l10n.tripBoosterBuy,
                  onTap: onBuy,
                  height: DesignExtras.rewardedHeight,
                  radius: LayoutTokens.ctaRadius,
                  labelStyle: DesignExtras.rewardedTitle,
                  sidePadding: DesignExtras.rewardedSidePadding,
                  semanticLabel: priceBadge == null
                      ? null
                      : l10n.pairLabel(l10n.tripBoosterBuy, priceBadge),
                  trailing: priceBadge == null
                      ? null
                      : PriceChip(label: priceBadge),
                )
              else
                CardText(l10n.tripBoosterShort(short, numbers.integer(short))),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                spacing: SpaceTokens.s4,
                children: [
                  const AppIcon(
                    'bonat',
                    size: DesignExtras.boosterAdBalanceIcon,
                  ),
                  Flexible(
                    child: CardText(
                      l10n.tripBoosterCardBalance(
                        card.bonat,
                        numbers.integer(card.bonat),
                      ),
                    ),
                  ),
                ],
              ),
              if (retry case final retry?) CardText(l10n.retryMessage(retry)),
            ],
          ),
        ),
        Center(
          child: AppButton.tertiary(
            key: closeKey,
            label: l10n.tripBoosterClose,
            onTap: onClose,
            height: DesignExtras.boosterAdCloseHeight,
            sidePadding: SpaceTokens.s16,
          ),
        ),
      ],
    );
  }
}
