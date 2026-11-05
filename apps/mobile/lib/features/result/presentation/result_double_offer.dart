// The result's ×2 (specs/018-m11-ads, contracts/seams.md
// "`ResultDoubleOffer`", `Result` boxes 42–46): «اقبض ×٢» over the doubled
// pay, and the decline link under it. One ad doubles the pay once; the
// result's own `doubled` read then shows it and drops this slot.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/ads/ads_providers.dart';
import 'package:wassal/core/ads/ads_service.dart';
import 'package:wassal/core/economy/economy.dart' show AdPlacement;
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/theme/components/buttons.dart';
import 'package:wassal/core/theme/components/pressable.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/result/domain/result_args.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

class ResultDoubleOffer extends ConsumerStatefulWidget {
  const ResultDoubleOffer({required this.args, super.key});

  final ResultArgs args;

  static const offerKey = Key('result.double.offer');
  static const declineKey = Key('result.double.decline');

  /// The link takes 44 to the touch where the board draws it 36 high, so
  /// the gap above it is 4 rather than 12 and the card below stays put.
  static const double _linkHeight = 44;

  @override
  ConsumerState<ResultDoubleOffer> createState() => _ResultDoubleOfferState();
}

class _ResultDoubleOfferState extends ConsumerState<ResultDoubleOffer> {
  bool _declined = false;
  bool _watching = false;

  String get _tripId => widget.args.result.tripId;

  Future<void> _watch() async {
    if (_watching) return;
    setState(() => _watching = true);
    try {
      await ref
          .read(adsServiceProvider)
          .watch(AdPlacement.resultDouble, tripId: _tripId);
    } finally {
      if (mounted) setState(() => _watching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final offer = ref.watch(
      adOfferNowProvider(AdPlacement.resultDouble, tripId: _tripId),
    );
    if (_declined || offer is Hidden || offer is LimitReached) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final numbers = ref.watch(numberFormatterProvider);
    final pay = widget.args.result.earningsJenehat;
    final payText = numbers.integer(pay);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: SpaceTokens.s4,
      children: [
        RewardedAdButton(
          key: ResultDoubleOffer.offerKey,
          large: true,
          ready: offer is Offered && !_watching,
          title: l10n.resultDoubleTitle,
          benefit: l10n.resultDoubleBenefit(numbers.integer(pay * 2), payText),
          unavailable: offer is NeedsNetwork ? l10n.adNeedsNetwork : null,
          onTap: () => unawaited(_watch()),
        ),
        Pressable(
          key: ResultDoubleOffer.declineKey,
          semanticLabel: l10n.resultDoubleDecline(payText),
          pressedOpacity: Pressable.disabledOpacity,
          onTap: () => setState(() => _declined = true),
          child: SizedBox(
            height: ResultDoubleOffer._linkHeight,
            child: Center(
              child: Text(
                l10n.resultDoubleDecline(payText),
                style: DesignExtras.resultDeclineLabel.copyWith(
                  color: ColorTokens.inkMuted,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
