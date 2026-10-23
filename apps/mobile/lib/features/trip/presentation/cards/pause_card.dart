// The pause (ux-spec «نافذة الإيقاف», FR-013; 008.5 `Pause`, research
// R13): the parked microbus, «واقفين على جنب» and its line, «كمّل المشوار»,
// «عيد المشوار» with its liter, «ارجع الموقف», and the sound and vibration
// switches, which save at once.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/components/buttons.dart';
import 'package:wassal/core/theme/components/controls.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/trip/presentation/cards/restart_button.dart';
import 'package:wassal/features/trip/presentation/cards/trip_card.dart';
import 'package:wassal/features/trip/trip_providers.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

class PauseCard extends StatelessWidget {
  const PauseCard({
    required this.onResume,
    required this.onRestart,
    required this.onHome,
    required this.restartEnabled,
    super.key,
  });

  final VoidCallback onResume;
  final VoidCallback onRestart;
  final VoidCallback onHome;
  final bool restartEnabled;

  static const resumeKey = ValueKey('trip-pause-resume');
  static const soundKey = ValueKey('trip-pause-sound');
  static const hapticsKey = ValueKey('trip-pause-haptics');
  static const restartKey = ValueKey('trip-pause-restart');
  static const homeKey = ValueKey('trip-pause-home');
  static const artKey = ValueKey('trip-pause-art');

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return TripCard(
      title: l10n.pauseTitle,
      titleStyle: DesignExtras.pauseTitle,
      art: const _ParkedMicrobus(key: artKey),
      scrim: DesignExtras.pauseScrim,
      designTop: DesignExtras.pauseTop,
      padding: DesignExtras.pausePadding,
      children: [
        Text(
          l10n.pauseSubtitle,
          textAlign: TextAlign.center,
          style: DesignExtras.dialogSubtitle.copyWith(
            color: ColorTokens.inkMuted,
          ),
        ),
        AppButton.primary(
          key: resumeKey,
          label: l10n.pauseResume,
          onTap: onResume,
          height: DesignExtras.pauseButtonHeight,
          radius: LayoutTokens.buttonRadius,
          labelStyle: DesignExtras.pauseButtonLabel,
        ),
        RestartButton(
          buttonKey: restartKey,
          enabled: restartEnabled,
          onRestart: onRestart,
        ),
        AppButton.tertiary(
          key: homeKey,
          label: l10n.pauseHome,
          onTap: onHome,
          expand: true,
          height: DesignExtras.failTileHeight,
        ),
        const _Switches(),
      ],
    );
  }
}

/// `Pause` box 8: the old microbus, parked, cropped from its art.
class _ParkedMicrobus extends StatelessWidget {
  const _ParkedMicrobus({super.key});

  static const _asset = 'assets/illustrations/vehicles/microbus_old.svg';

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(RadiusTokens.s),
    child: SizedBox.fromSize(
      size: DesignExtras.pauseArt,
      child: SvgPicture.asset(
        _asset,
        fit: BoxFit.cover,
        excludeFromSemantics: true,
      ),
    ),
  );
}

/// `Pause` box 16: the two switches side by side under a 2 pt `track`
/// rule, sound first.
class _Switches extends ConsumerWidget {
  const _Switches();

  static const _rule = 2.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(tripSettingsProvider);
    final notifier = ref.read(tripSettingsProvider.notifier);
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: ColorTokens.track, width: _rule),
        ),
      ),
      child: Padding(
        // A decoration's border takes no room of its own.
        padding: const EdgeInsets.only(top: _rule + SpaceTokens.s4),
        child: Row(
          spacing: SpaceTokens.s10,
          children: [
            Expanded(
              child: AppSwitch(
                key: PauseCard.soundKey,
                label: l10n.tripPauseSound,
                value: settings.soundOn,
                onChanged: (on) => unawaited(notifier.setSound(on: on)),
                framed: false,
              ),
            ),
            Expanded(
              child: AppSwitch(
                key: PauseCard.hapticsKey,
                label: l10n.tripPauseHaptics,
                value: settings.hapticsOn,
                onChanged: (on) => unawaited(notifier.setHaptics(on: on)),
                framed: false,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
