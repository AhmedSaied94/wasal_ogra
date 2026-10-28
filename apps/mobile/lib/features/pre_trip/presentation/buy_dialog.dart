// Buying a booster from the card (specs/013-m08-home-result,
// contracts/pre-trip-card.md "Buying a booster", research R7): 008.5's
// spend confirmation with M02's booster content. Only its buttons close
// it. A save that failed says so, and buying again sends the same request.
import 'package:content_models/content_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/economy/economy.dart';
import 'package:wassal/core/economy/economy_providers.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/theme/components/app_icon.dart';
import 'package:wassal/core/theme/components/overlays.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/features/pre_trip/application/booster_purchase.dart';
import 'package:wassal/features/pre_trip/presentation/booster_tiles.dart';
import 'package:wassal/features/trip/presentation/cards/trip_card.dart';
import 'package:wassal/features/trip/presentation/dashboard/boosters_row.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

Future<void> showBuyDialog(
  BuildContext context, {
  required BoosterId booster,
  required int priceBonat,
  required BoosterPurchase purchase,
}) => showAppDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) =>
      BuyDialog(booster: booster, priceBonat: priceBonat, purchase: purchase),
);

class BuyDialog extends ConsumerStatefulWidget {
  const BuyDialog({
    required this.booster,
    required this.priceBonat,
    required this.purchase,
    super.key,
  });

  final BoosterId booster;
  final int priceBonat;
  final BoosterPurchase purchase;

  static const buyKey = Key('BuyDialog.buy');
  static const closeKey = Key('BuyDialog.close');

  @override
  ConsumerState<BuyDialog> createState() => _BuyDialogState();
}

class _BuyDialogState extends ConsumerState<BuyDialog> {
  bool _failed = false;

  Future<void> _buy() async {
    final outcome = await widget.purchase.buy(widget.booster);
    if (outcome == null || !mounted) return;
    switch (outcome) {
      case OpApplied():
        Navigator.of(context).pop();
      // Short: the balance below says so, from the economy's view.
      case OpRefused(code: EconomyRefusal.insufficientFunds):
        setState(() => _failed = false);
      // Anything else closes it, as the trip's card does.
      case OpRefused():
        Navigator.of(context).pop();
      case OpWriteFailed():
        setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final numbers = ref.watch(numberFormatterProvider);
    final bonat = ref.watch(economyViewProvider.select((view) => view.bonat));
    final missing = widget.priceBonat - bonat;
    return TripDialog(
      title: boosterTileName(l10n, widget.booster),
      art: AppIcon(
        BoosterButton.icons[widget.booster] ?? 'booster_traffic',
        size: DesignExtras.confirmArt,
      ),
      children: [
        CardText(l10n.tripBoosterCardPrice(numbers.integer(widget.priceBonat))),
        CardText(l10n.tripBoosterCardBalance(bonat, numbers.integer(bonat))),
        if (missing > 0)
          CardText(l10n.tripBoosterShort(missing, numbers.integer(missing))),
        if (_failed) CardText(l10n.tripRetryPurchase),
        CardActions(
          confirm: missing > 0
              ? null
              : CardConfirm(
                  key: BuyDialog.buyKey,
                  label: l10n.preTripBuy,
                  onTap: _buy,
                ),
          dismiss: CardTile(
            key: BuyDialog.closeKey,
            label: l10n.tripBoosterClose,
            onTap: () => Navigator.of(context).pop(),
          ),
        ),
      ],
    );
  }
}
