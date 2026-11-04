// Internal builds' ads card (specs/018-m11-ads, T032, FR-029): consent and
// `canRequestAds`, each unit's readiness, the last piggy reference with
// its `ads_dev_callback` line, and a «show» button per placement, disabled
// while a trip runs. Dev builds also get the consent test geography and
// «reset consent» (research R6). Labels and values are identifiers, as the
// sync card's. Prod never builds it (the Home debug sheet is internal).
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/bootstrap/flavor.dart';
import 'package:wassal/core/account/account_providers.dart';
import 'package:wassal/core/ads/ads_gateway.dart';
import 'package:wassal/core/ads/ads_providers.dart';
import 'package:wassal/core/economy/economy.dart';
import 'package:wassal/core/theme/components/buttons.dart';
import 'package:wassal/core/theme/components/containers.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/trip/trip_providers.dart';

class AdsDebugCard extends ConsumerStatefulWidget {
  const AdsDebugCard({super.key});

  static const copyKey = ValueKey('ads-debug-copy');
  static const resetKey = ValueKey('ads-debug-reset');
  static ValueKey<String> showKey(AdPlacement placement) =>
      ValueKey('ads-debug-show-${placement.wire}');
  static ValueKey<String> geographyKey(ConsentGeography geography) =>
      ValueKey('ads-debug-geo-${geography.name}');

  /// The line the copy button puts on the clipboard.
  static String callbackLine({
    required String? player,
    required String nonce,
  }) =>
      'uv run manage.py ads_dev_callback '
      '${player == null ? '' : '--user $player '}--nonce $nonce';

  @override
  ConsumerState<AdsDebugCard> createState() => _AdsDebugCardState();
}

class _AdsDebugCardState extends ConsumerState<AdsDebugCard> {
  String? _lastShow;

  Future<void> _show(AdPlacement placement) async {
    final earned = await ref.read(adsServiceProvider).showRewarded(placement);
    if (mounted) {
      setState(
        () => _lastShow =
            '${placement.wire}: ${earned ? 'rewarded' : 'no reward'}',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final gateway = ref.watch(adsGatewayProvider);
    final service = ref.watch(adsServiceProvider);
    final piggy = ref.watch(piggyServiceProvider);
    final running = ref.watch(tripRunningProvider);
    final dev = ref.watch(flavorProvider) == Flavor.dev;
    final controls = gateway is AdsDebugControls
        ? gateway as AdsDebugControls
        : null;
    return AnimatedBuilder(
      animation: Listenable.merge([
        running,
        piggy.lastNonce,
        for (final unit in AdUnit.values) gateway.readiness(unit),
      ]),
      builder: (context, _) {
        final nonce = piggy.lastNonce.value;
        return AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: SpaceTokens.s8,
            children: [
              Text(
                // Developer text, as the playtest tools'.
                'ads',
                textDirection: TextDirection.ltr,
                style: TypeTokens.displayS.copyWith(color: ColorTokens.ink),
              ),
              for (final (label, value) in [
                ('can_request_ads', '${service.canRequestAds}'),
                if (controls != null)
                  ('consent_form_shown', '${controls.formShown}'),
                for (final unit in AdUnit.values)
                  (unit.name, gateway.readiness(unit).value.name),
                ('piggy_nonce', nonce ?? 'none'),
                if (_lastShow != null) ('last_show', _lastShow!),
              ])
                _Row(label: label, value: value),
              if (nonce != null)
                AppButton.secondary(
                  key: AdsDebugCard.copyKey,
                  label: 'copy ads_dev_callback',
                  size: AppButtonSize.compact,
                  onTap: () => unawaited(
                    Clipboard.setData(
                      ClipboardData(
                        text: AdsDebugCard.callbackLine(
                          player: ref.read(profileProvider)?.playerId,
                          nonce: nonce,
                        ),
                      ),
                    ),
                  ),
                ),
              for (final placement in AdPlacement.values)
                AppButton.secondary(
                  key: AdsDebugCard.showKey(placement),
                  label: 'show ${placement.wire}',
                  size: AppButtonSize.compact,
                  enabled: !running.value,
                  onTap: () => unawaited(_show(placement)),
                ),
              if (dev && controls != null) ...[
                _Row(label: 'test_geography', value: controls.geography.name),
                Row(
                  textDirection: TextDirection.ltr,
                  spacing: SpaceTokens.s8,
                  children: [
                    for (final geography in ConsentGeography.values)
                      Expanded(
                        child: AppButton.secondary(
                          key: AdsDebugCard.geographyKey(geography),
                          label: geography.name,
                          size: AppButtonSize.compact,
                          enabled: controls.geography != geography,
                          onTap: () =>
                              setState(() => controls.geography = geography),
                        ),
                      ),
                  ],
                ),
                AppButton.secondary(
                  key: AdsDebugCard.resetKey,
                  label: 'reset consent',
                  size: AppButtonSize.compact,
                  onTap: () => unawaited(controls.resetConsent()),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    textDirection: TextDirection.ltr,
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: SpaceTokens.s8,
    children: [
      Text(
        label,
        textDirection: TextDirection.ltr,
        style: TypeTokens.label.copyWith(color: ColorTokens.ink2),
      ),
      Expanded(
        child: Text(
          value,
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.end,
          style: TypeTokens.caption.copyWith(color: ColorTokens.ink),
        ),
      ),
    ],
  );
}
