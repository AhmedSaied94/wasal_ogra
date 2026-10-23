// A booster the player has none of (contracts/trip-controller.md "Booster
// purchase"): its price in BONAT and the player's balance, «اشتري واستعمل»,
// or «ناقصك …» when short, and «مش دلوقتي». The clock waits. A save that
// failed says so here, and buying again sends the same request.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/theme/components/primary_button.dart';
import 'package:wassal/core/theme/components/secondary_button.dart';
import 'package:wassal/core/theme/tokens/space.dart';
import 'package:wassal/features/trip/application/trip_phase.dart';
import 'package:wassal/features/trip/presentation/cards/trip_card.dart';
import 'package:wassal/features/trip/presentation/trip_text.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

class BoosterCard extends ConsumerWidget {
  const BoosterCard({
    required this.card,
    required this.retry,
    required this.onBuy,
    required this.onClose,
    super.key,
  });

  final BoosterCardModel card;

  /// A purchase that failed to save, or null.
  final TripRetry? retry;
  final VoidCallback onBuy;
  final VoidCallback onClose;

  static const buyKey = ValueKey('trip-booster-buy');
  static const closeKey = ValueKey('trip-booster-close');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final numbers = ref.watch(numberFormatterProvider);
    final price = card.priceBonat;
    final short = card.shortBy;
    return TripCard(
      title: l10n.boosterName(card.booster),
      children: [
        if (price != null)
          CardText(l10n.tripBoosterCardPrice(numbers.integer(price))),
        CardText(l10n.tripBoosterCardBalance(numbers.integer(card.bonat))),
        if (short != null)
          CardText(l10n.tripBoosterShort(numbers.integer(short))),
        if (retry case final retry?) CardText(l10n.retryMessage(retry)),
        if (short == null) ...[
          PrimaryButton(
            key: buyKey,
            label: l10n.tripBoosterBuy,
            onPressed: onBuy,
          ),
          const SizedBox(height: SpaceTokens.m),
        ],
        SecondaryButton(
          key: closeKey,
          label: l10n.tripBoosterClose,
          onPressed: onClose,
        ),
      ],
    );
  }
}
