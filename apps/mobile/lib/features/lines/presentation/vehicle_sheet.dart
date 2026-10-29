// A vehicle's sheet (specs/014-m09-lines-vehicles, contracts/buy-vehicle.md,
// HANDOFF `BuyVehicle`, §9.2, `BuyVehicleShort`, `BuyVehicleOwned`,
// `BuyVehicleNotForSale`): the preview, what it brings, and either its
// price against the jenehat with «اشتريها» and «لسه», or why there is
// nothing to buy in a status row over one «تمام». The player's own vehicle
// shows its preview and status only. The sheet is the confirmation: no
// dialog before the buy. Closing spends nothing.
import 'dart:async';

import 'package:content_models/content_models.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/content/content_providers.dart';
import 'package:wassal/core/economy/economy.dart' hide Owned;
import 'package:wassal/core/economy/economy_providers.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/progress/domain/playable.dart';
import 'package:wassal/core/routing/nav_guard.dart';
import 'package:wassal/core/theme/components/buttons.dart';
import 'package:wassal/core/theme/components/containers.dart';
import 'package:wassal/core/theme/components/overlays.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/lines/application/vehicle_offer_provider.dart';
import 'package:wassal/features/lines/application/vehicle_purchase.dart';
import 'package:wassal/features/lines/domain/vehicle_offer.dart';
import 'package:wassal/features/lines/presentation/benefits_row.dart';
import 'package:wassal/features/lines/presentation/board_sheet.dart';
import 'package:wassal/features/lines/presentation/impact_line.dart';
import 'package:wassal/features/lines/presentation/price_card.dart';
import 'package:wassal/features/lines/presentation/status_row.dart';
import 'package:wassal/features/lines/presentation/vehicle_preview.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

class VehicleSheet extends ConsumerStatefulWidget {
  const VehicleSheet({required this.vehicle, super.key});

  final VehicleId vehicle;

  static const closeKey = Key('VehicleSheet.close');
  static const buyKey = Key('VehicleSheet.buy');
  static const laterKey = Key('VehicleSheet.later');
  static const doneKey = Key('VehicleSheet.done');
  static const statusKey = Key('VehicleSheet.status');
  static const shortfallKey = Key('VehicleSheet.shortfall');
  static const retryKey = Key('VehicleSheet.retry');

  /// The board's gutter is 16 and its foot 24; the shared sheet's are 14.
  static const double _sideExtra = SpaceTokens.s2;
  static const double _footExtra = SpaceTokens.s10;

  /// `BuyVehicle` block 2: the blocks' gap.
  static const double gap = SpaceTokens.s12;

  /// `BuyVehicle` block 2g: both buttons 64 high, radius 22.
  static const double buttonHeight = 64;

  /// `BuyVehicle` block 2: the sheet's top.
  static const double top = 154;

  @override
  ConsumerState<VehicleSheet> createState() => _VehicleSheetState();
}

class _VehicleSheetState extends ConsumerState<VehicleSheet> {
  late final _purchase = VehiclePurchase(
    ref.read(economyProvider).requireValue,
  );
  bool _leaving = false;
  bool _writeFailed = false;

  /// A vehicle the pack lacks: back to the map, once.
  void _leave() {
    if (_leaving) return;
    _leaving = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) NavGuard.go(context, '/lines');
    });
  }

  void _close() => unawaited(Navigator.of(context).maybePop());

  Future<void> _buy(VehicleOffer offer) async {
    final l10n = AppLocalizations.of(context);
    final view = View.of(context);
    final direction = Directionality.of(context);
    final content = ref.read(contentSourceProvider);
    final outcome = await _purchase.buy(offer);
    if (!mounted || outcome == null) return;
    switch (outcome) {
      case OpApplied():
        final line = switch (offer.opensLine) {
          final LineId line => content.line(line)?.name.arEg,
          null => null,
        };
        unawaited(
          SemanticsService.sendAnnouncement(
            view,
            line == null
                ? l10n.buyVehicleBought(offer.name)
                : l10n.buyVehicleBoughtA11y(offer.name, line),
            direction,
          ),
        );
        NavGuard.go(context, '/lines');
      case OpWriteFailed():
        setState(() => _writeFailed = true);
      case OpRefused(code: EconomyRefusal.insufficientFunds) ||
          OpRefused(code: EconomyRefusal.alreadyOwned):
        // The view shows the shortfall, or the owned sheet.
        setState(() => _writeFailed = false);
      case OpRefused():
        showAppToast(context, l10n.buyVehicleNotForSaleToast);
        NavGuard.go(context, '/lines');
    }
  }

  @override
  Widget build(BuildContext context) {
    final offer = ref.watch(vehicleOfferOfProvider(widget.vehicle));
    if (offer == null) {
      _leave();
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final numbers = ref.watch(numberFormatterProvider);
    final sale = offer.sale;
    final status = switch (sale) {
      Owned() when offer.starter => l10n.buyVehicleOwnedStarter,
      Owned() => l10n.buyVehicleOwned,
      NeedsFirst(:final vehicle) => l10n.buyVehicleNeedsFirst(
        ref.watch(contentSourceProvider).vehicle(vehicle)?.name.arEg ?? '',
      ),
      NoPrice() => l10n.buyVehicleNoPrice,
      ForSale() => null,
    };
    final shortfall = offer.shortfall;
    // The player's own vehicle: the preview and its status only, the sheet
    // as tall as that (`BuyVehicleOwned`).
    final owned = sale is Owned;
    final scroll = SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: VehicleSheet.gap,
        children: [
          VehiclePreview(vehicle: offer.vehicle),
          if (!owned) BenefitsRow(offer: offer),
          if (offer.listPrice case final price? when !owned)
            PriceCard(price: price, jenehat: offer.jenehat),
          if (offer.impact case final impact? when shortfall == null)
            ImpactLine(impact: impact),
        ],
      ),
    );
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(
        VehicleSheet._sideExtra,
        0,
        VehicleSheet._sideExtra,
        VehicleSheet._footExtra,
      ),
      child: Column(
        mainAxisSize: owned ? MainAxisSize.min : MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(name: offer.name, onClose: _close),
          const SizedBox(height: VehicleSheet.gap),
          if (owned) Flexible(child: scroll) else Expanded(child: scroll),
          if (shortfall != null) ...[
            const SizedBox(height: VehicleSheet.gap),
            // A refusal says its shortfall to a screen reader too.
            Semantics(
              liveRegion: true,
              child: Text(
                key: VehicleSheet.shortfallKey,
                l10n.buyVehicleShortfall(numbers.integer(shortfall)),
                textAlign: TextAlign.center,
                style: DesignExtras.buyVehicleShortfall.copyWith(
                  color: ColorTokens.dangerInk,
                ),
              ),
            ),
            const SizedBox(height: SpaceTokens.s8),
            ProgressBar(
              value: offer.jenehat / (offer.price ?? 1),
              color: ProgressColor.gold,
            ),
          ],
          if (_writeFailed) ...[
            const SizedBox(height: VehicleSheet.gap),
            // A write that failed is announced, not just drawn.
            Semantics(
              liveRegion: true,
              child: Text(
                key: VehicleSheet.retryKey,
                l10n.tripRetryPurchase,
                textAlign: TextAlign.center,
                style: DesignExtras.buyVehicleShortfall.copyWith(
                  color: ColorTokens.dangerInk,
                ),
              ),
            ),
          ],
          if (status != null) ...[
            const SizedBox(height: VehicleSheet.gap),
            Semantics(
              key: VehicleSheet.statusKey,
              liveRegion: true,
              child: owned
                  ? StatusRow.owned(text: status)
                  : StatusRow.locked(text: status),
            ),
          ],
          // `BuyVehicleShort`: the bar sits 10 over the buttons.
          SizedBox(
            height: shortfall == null ? VehicleSheet.gap : SpaceTokens.s10,
          ),
          if (sale is ForSale)
            Row(
              spacing: SpaceTokens.s10,
              children: [
                Expanded(
                  flex: 2,
                  child: AppButton.primary(
                    key: VehicleSheet.buyKey,
                    label: l10n.buyVehicleBuy,
                    height: VehicleSheet.buttonHeight,
                    radius: LayoutTokens.ctaRadius,
                    labelStyle: DesignExtras.buyVehicleBuy,
                    enabled: offer.affordable,
                    onTap: () => unawaited(_buy(offer)),
                  ),
                ),
                Expanded(
                  child: AppButton.secondary(
                    key: VehicleSheet.laterKey,
                    label: l10n.buyVehicleLater,
                    height: VehicleSheet.buttonHeight,
                    radius: LayoutTokens.ctaRadius,
                    onTap: _close,
                  ),
                ),
              ],
            )
          else
            // Nothing to buy: one close button, the primary one
            // (`BuyVehicleOwned`, `BuyVehicleNotForSale`).
            AppButton.primary(
              key: VehicleSheet.doneKey,
              label: l10n.buyVehicleDone,
              height: VehicleSheet.buttonHeight,
              radius: LayoutTokens.ctaRadius,
              labelStyle: DesignExtras.buyVehicleBuy,
              onTap: _close,
            ),
        ],
      ),
    );
    return owned ? content : BoardSheet(top: VehicleSheet.top, child: content);
  }
}

/// The vehicle's name and ✕ (`BuyVehicle` block 2b).
class _Header extends StatelessWidget {
  const _Header({required this.name, required this.onClose});

  final String name;
  final VoidCallback onClose;

  static const double _top = SpaceTokens.s14;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: _top),
    child: Row(
      spacing: SpaceTokens.s10,
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              name,
              style: DesignExtras.lineDetailsTitle.copyWith(
                color: ColorTokens.ink,
              ),
            ),
          ),
        ),
        IconCircleButton(
          key: VehicleSheet.closeKey,
          icon: 'close',
          semanticLabel: AppLocalizations.of(context).closeLabel,
          inSheet: true,
          onTap: onClose,
        ),
      ],
    ),
  );
}
