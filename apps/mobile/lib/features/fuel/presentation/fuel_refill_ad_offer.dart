// A full tank, two ways (specs/018-m11-ads, contracts/seams.md
// "`FuelRefillAdOffer`", the owner's `NoFuelAd` and `NoFuelAdLimit`
// boards): the refill ad and, beside it, the BONAT refill «فوّل الخزان»,
// two equal tiles. The BONAT option is next to the ad wherever this goes
// (constitution IX). The ad's tile says how many are left today, that
// none is, that it isn't loaded, or that it needs the network; the BONAT
// tile says what is missing or that its save failed. Hidden with a full
// tank. At the cap the ad's tile is «خلصت النهارده» alone, faded.
import 'dart:async';

import 'package:content_models/content_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/ads/ads_providers.dart';
import 'package:wassal/core/ads/ads_service.dart';
import 'package:wassal/core/content/content_providers.dart';
import 'package:wassal/core/economy/domain/spend_rules.dart' show refuelFullSku;
import 'package:wassal/core/economy/economy.dart';
import 'package:wassal/core/economy/economy_providers.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/theme/components/app_icon.dart';
import 'package:wassal/core/theme/components/pressable.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/apartment/presentation/price_chip.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

class FuelRefillAdOffer extends ConsumerStatefulWidget {
  const FuelRefillAdOffer({required this.onFilled, super.key});

  /// The tank is full: the trip route retries the start; the sheet closes.
  final VoidCallback onFilled;

  static const adKey = ValueKey('fuel-refill-ad');
  static const bonatKey = ValueKey('fuel-refill-bonat');
  static const noteKey = ValueKey('fuel-refill-note');

  @override
  ConsumerState<FuelRefillAdOffer> createState() => _FuelRefillAdOfferState();
}

class _FuelRefillAdOfferState extends ConsumerState<FuelRefillAdOffer> {
  bool _busy = false;

  /// The BONAT refill's request, held until it is answered (a retry after a
  /// failed write sends the same one).
  TxnId? _buyId;
  bool _writeFailed = false;
  int? _shortBy;

  int? get _price => switch (ref
      .read(contentSourceProvider)
      .price(SkuKind.fuel, refuelFullSku)) {
    final price? when price.currency == Currency.bonat => price.amount,
    _ => null,
  };

  @override
  void initState() {
    super.initState();
    // Nothing else loads the refill's unit on the way here (an empty tank
    // goes to the sheet before the between-trips checkpoint). Not while the
    // offer is hidden: the tutorial's consent waits (research R15).
    if (ref.read(adOfferNowProvider(AdPlacement.fuelRefill)) is! Hidden) {
      ref.read(adWarmUpProvider)(AdPlacement.fuelRefill);
    }
  }

  Future<void> _watch() async {
    if (_busy) return;
    setState(() => _busy = true);
    RewardOutcome outcome = const NoReward();
    try {
      outcome = await ref
          .read(adsServiceProvider)
          .watch(AdPlacement.fuelRefill);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted && outcome is RewardApplied) widget.onFilled();
  }

  Future<void> _buy() async {
    if (_busy) return;
    final economy = ref.read(economyProvider).requireValue;
    final id = _buyId ??= economy.newRequestId();
    setState(() => _busy = true);
    final outcome = await economy.buy(
      id,
      kind: SkuKind.fuel,
      skuId: refuelFullSku,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _writeFailed = outcome is OpWriteFailed;
      if (outcome is! OpWriteFailed) _buyId = null;
      _shortBy = switch (outcome) {
        OpRefused(code: EconomyRefusal.insufficientFunds) =>
          (_price ?? 0) - economy.view.bonat,
        _ => null,
      };
    });
    if (outcome is OpApplied) widget.onFilled();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final numbers = ref.watch(numberFormatterProvider);
    final fuel = ref.watch(economyViewProvider).fuel;
    if (fuel.liters >= fuel.max || fuel.unlimitedUntilMs != null) {
      return const SizedBox.shrink();
    }
    final offer = ref.watch(adOfferNowProvider(AdPlacement.fuelRefill));
    final price = _price;
    final note = _writeFailed
        ? l10n.tripRetryPurchase
        : switch (_shortBy) {
            final short? when short > 0 => l10n.tripBoosterShort(
              short,
              numbers.integer(short),
            ),
            _ => null,
          };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: SpaceTokens.s8,
      children: [
        // Equal tiles: with large text the taller one sets both.
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: SpaceTokens.s10,
            children: [
              if (offer is! Hidden)
                Expanded(
                  child: _AdTile(offer: offer, busy: _busy, onTap: _watch),
                ),
              if (price != null)
                Expanded(
                  child: _Tile(
                    key: FuelRefillAdOffer.bonatKey,
                    icon: 'fuel',
                    title: l10n.refillBonatTitle,
                    semanticLabel: l10n.pairLabel(
                      l10n.refillBonatTitle,
                      l10n.tripBoosterPriceBadge(numbers.integer(price)),
                    ),
                    enabled: !_busy,
                    onTap: () => unawaited(_buy()),
                    below: PriceChip(
                      label: l10n.tripBoosterPriceBadge(numbers.integer(price)),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (note != null)
          Text(
            note,
            key: FuelRefillAdOffer.noteKey,
            textAlign: TextAlign.center,
            style: TypeTokens.caption.copyWith(color: ColorTokens.inkMuted),
          ),
      ],
    );
  }
}

/// The ad's tile, by what the ads layer says now.
class _AdTile extends ConsumerWidget {
  const _AdTile({required this.offer, required this.busy, required this.onTap});

  final AdOffer offer;
  final bool busy;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final numbers = ref.watch(numberFormatterProvider);
    final line = switch (offer) {
      Offered(:final left?) => l10n.refillAdLeft(left, numbers.integer(left)),
      Offered() => null,
      NotReady() => l10n.adNotReady,
      NeedsNetwork() => l10n.adNeedsNetwork,
      // `NoFuelAdLimit` draws «خلصت النهارده» alone, as the title.
      LimitReached() || Hidden() => null,
    };
    final limit = offer is LimitReached;
    final title = limit ? l10n.adLimitReached : l10n.refillAdTitle;
    final ready = offer is Offered && !busy;
    return _Tile(
      key: FuelRefillAdOffer.adKey,
      icon: limit ? 'ad_screen' : 'ad_play_on_primary',
      title: title,
      semanticLabel: line == null ? title : l10n.pairLabel(title, line),
      enabled: ready,
      onTap: () => unawaited(onTap()),
      below: line == null
          ? null
          : Text(
              line,
              textAlign: TextAlign.center,
              style: TypeTokens.label.copyWith(color: ColorTokens.primarySoft),
            ),
    );
  }
}

/// One of the two `primary` tiles: an icon over its title, and a line or a
/// chip under it. Disabled, it is faded with no lip (`NoFuelAdLimit`).
class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.title,
    required this.semanticLabel,
    required this.enabled,
    required this.onTap,
    this.below,
    super.key,
  });

  final String icon;
  final String title;
  final String semanticLabel;
  final bool enabled;
  final VoidCallback onTap;
  final Widget? below;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(RadiusTokens.card);
    return Pressable(
      onTap: onTap,
      enabled: enabled,
      lip: LipTokens.primary,
      borderRadius: radius,
      semanticLabel: semanticLabel,
      child: Container(
        constraints: const BoxConstraints(
          minHeight: DesignExtras.refillTileHeight,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: SpaceTokens.s10,
          vertical: SpaceTokens.s8,
        ),
        decoration: BoxDecoration(
          color: ColorTokens.primary,
          borderRadius: radius,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: SpaceTokens.s4,
          children: [
            AppIcon(icon, size: DesignExtras.refillTileIcon),
            Text(
              title,
              textAlign: TextAlign.center,
              style: DesignExtras.refillTileTitle.copyWith(
                color: ColorTokens.paper,
              ),
            ),
            ?below,
          ],
        ),
      ),
    );
  }
}
