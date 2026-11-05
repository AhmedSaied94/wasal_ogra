// The morning piggy on Home (specs/018-m11-ads, contracts/seams.md
// "`PiggyBanner`"; HANDOFF Home row 6, `HomeStates` row 7): the pig, «حصّالة
// الصبح» over its line, and a chip that says what a tap does: «ببلاش» when
// an ad is loaded, «الإعلان مش جاهز» when none is, «محتاج نت» offline, and
// the wheel while the phone asks the server for the reward. The outcome
// opens the reward dialog or a toast, and the banner hides for the day.
// Home's slot is empty while the state is hidden (`adsOverrides`).
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/ads/ads_providers.dart';
import 'package:wassal/core/ads/piggy_service.dart';
import 'package:wassal/core/art/rive_art.dart';
import 'package:wassal/features/home/application/piggy_banner_state.dart';
import 'package:wassal/core/theme/components/app_icon.dart';
import 'package:wassal/core/theme/components/overlays.dart';
import 'package:wassal/core/theme/components/pressable.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/home/presentation/piggy_cards.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

class PiggyBanner extends ConsumerWidget {
  const PiggyBanner({super.key});

  static const bannerKey = ValueKey('home-piggy');
  static const chipKey = ValueKey('home-piggy-chip');

  static const double _icon = 30;
  static const double _chipIcon = 16;
  static const double _chipHeight = 32;
  static const double _chipMinWidth = 82;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(piggyBannerProvider);
    if (state == PiggyBannerState.hidden) return const SizedBox.shrink();
    final chip = switch (state) {
      PiggyBannerState.ready => _Chip(
        label: l10n.piggyCta,
        trailing: const AppIcon('ad_play_on_primary', size: _chipIcon),
      ),
      PiggyBannerState.notReady => _Chip(label: l10n.adNotReady, muted: true),
      PiggyBannerState.offline => _Chip(
        label: l10n.adNeedsNetwork,
        muted: true,
      ),
      PiggyBannerState.asking || PiggyBannerState.hidden => const _Chip(
        trailing: SizedBox.square(
          dimension: _chipIcon,
          child: RiveArtView(
            artboard: 'LoadingWheel',
            fallback: AppIcon('ad_screen', size: _chipIcon),
          ),
        ),
      ),
    };
    final label = switch (state) {
      PiggyBannerState.asking => l10n.piggyAsking,
      PiggyBannerState.ready => l10n.pairLabel(l10n.piggyTitle, l10n.piggyCta),
      PiggyBannerState.offline => l10n.pairLabel(
        l10n.piggyTitle,
        l10n.adNeedsNetwork,
      ),
      _ => l10n.pairLabel(l10n.piggyTitle, l10n.adNotReady),
    };
    final banner = Container(
      // The body wraps on a narrow phone or with large text; Home's slot
      // grows with it.
      padding: const EdgeInsets.symmetric(
        horizontal: SpaceTokens.s12,
        vertical: SpaceTokens.s6,
      ),
      decoration: BoxDecoration(
        color: ColorTokens.sunSoft,
        borderRadius: BorderRadius.circular(RadiusTokens.bubble),
      ),
      child: Row(
        spacing: SpaceTokens.s10,
        children: [
          AppIcon(
            state == PiggyBannerState.offline ? 'piggy_alt' : 'piggy',
            size: _icon,
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.piggyTitle,
                  maxLines: 1,
                  style: DesignExtras.piggyBannerTitle.copyWith(
                    color: ColorTokens.ink,
                  ),
                ),
                Text(
                  l10n.piggyBody,
                  style: DesignExtras.piggyBannerBody.copyWith(
                    color: ColorTokens.ink2,
                  ),
                ),
              ],
            ),
          ),
          KeyedSubtree(key: chipKey, child: chip),
        ],
      ),
    );
    // Offline it is no control at all (`HomeStates` row 7): faded, no lip.
    if (state == PiggyBannerState.offline) {
      return Semantics(
        key: bannerKey,
        label: label,
        excludeSemantics: true,
        child: Opacity(opacity: Pressable.disabledOpacity, child: banner),
      );
    }
    return Pressable(
      key: bannerKey,
      onTap: () => unawaited(_watch(context, ref)),
      enabled: state == PiggyBannerState.ready,
      lip: LipTokens.sunSoft,
      borderRadius: BorderRadius.circular(RadiusTokens.bubble),
      semanticLabel: label,
      child: banner,
    );
  }

  /// The ad, the asks, then the outcome's card. What shows it is taken
  /// before the wait: the banner hides once the asking ends.
  Future<void> _watch(BuildContext context, WidgetRef ref) async {
    final navigator = Navigator.of(context);
    final overlay = Overlay.of(context, rootOverlay: true);
    final l10n = AppLocalizations.of(context);
    final outcome = await ref.read(piggyServiceProvider).watch();
    switch (outcome) {
      case PiggyArrivedNow(:final jenehat, :final bonat):
        if (!navigator.mounted) return;
        unawaited(
          navigator.push(
            appDialogRoute<void>(
              context: navigator.context,
              builder: (_) =>
                  PiggyArrivedDialog(jenehat: jenehat, bonat: bonat),
            ),
          ),
        );
      case PiggyUsedToday():
        if (overlay.mounted) {
          showAppToastOn(
            overlay,
            l10n.piggyUsed,
            leading: const PiggyToastIcon(),
          );
        }
      case PiggyComesLater():
        if (overlay.mounted) {
          showAppToastOn(
            overlay,
            l10n.piggyLater,
            leading: const PiggyToastIcon(later: true),
          );
        }
      case null:
        break;
    }
  }
}

/// The banner's chip: `primary` with «ببلاش», or `paper` when the ad can't
/// be watched now.
class _Chip extends StatelessWidget {
  const _Chip({this.label, this.trailing, this.muted = false});

  final String? label;
  final Widget? trailing;
  final bool muted;

  @override
  Widget build(BuildContext context) => Container(
    height: PiggyBanner._chipHeight,
    constraints: const BoxConstraints(minWidth: PiggyBanner._chipMinWidth),
    padding: const EdgeInsets.symmetric(horizontal: SpaceTokens.s12),
    decoration: BoxDecoration(
      color: muted ? ColorTokens.paper : ColorTokens.primary,
      borderRadius: BorderRadius.circular(RadiusTokens.pill),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      spacing: SpaceTokens.s4,
      children: [
        if (label case final label?)
          Text(
            label,
            style: TypeTokens.label
                .weight(700)
                .copyWith(color: muted ? ColorTokens.ink : ColorTokens.paper),
          ),
        ?trailing,
      ],
    ),
  );
}
