// The pause (ux-spec «نافذة الإيقاف», FR-013): «كمّل المشوار», «عيد
// المشوار» with its liter, «ارجع الموقف», and the sound and vibration
// switches, which save at once.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/app_theme.dart';
import 'package:wassal/core/theme/components/primary_button.dart';
import 'package:wassal/core/theme/components/secondary_button.dart';
import 'package:wassal/core/theme/tokens/shape.dart';
import 'package:wassal/core/theme/tokens/space.dart';
import 'package:wassal/core/theme/tokens/typography.dart';
import 'package:wassal/features/trip/presentation/cards/restart_button.dart';
import 'package:wassal/features/trip/presentation/cards/trip_card.dart';
import 'package:wassal/features/trip/trip_providers.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

class PauseCard extends ConsumerWidget {
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

  static const soundKey = ValueKey('trip-pause-sound');
  static const hapticsKey = ValueKey('trip-pause-haptics');
  static const restartKey = ValueKey('trip-pause-restart');
  static const homeKey = ValueKey('trip-pause-home');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(tripSettingsProvider);
    final notifier = ref.read(tripSettingsProvider.notifier);
    return TripCard(
      title: l10n.pauseTitle,
      children: [
        PrimaryButton(label: l10n.pauseResume, onPressed: onResume),
        const SizedBox(height: SpaceTokens.m),
        RestartButton(
          buttonKey: restartKey,
          enabled: restartEnabled,
          onRestart: onRestart,
        ),
        const SizedBox(height: SpaceTokens.m),
        SecondaryButton(key: homeKey, label: l10n.pauseHome, onPressed: onHome),
        const SizedBox(height: SpaceTokens.m),
        _Toggle(
          key: soundKey,
          label: l10n.tripPauseSound,
          value: settings.soundOn,
          onChanged: (on) => notifier.setSound(on: on),
        ),
        _Toggle(
          key: hapticsKey,
          label: l10n.tripPauseHaptics,
          value: settings.hapticsOn,
          onChanged: (on) => notifier.setHaptics(on: on),
        ),
      ],
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.label,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final String label;
  final bool value;
  final Future<void> Function(bool on) onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return MergeSemantics(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: ShapeTokens.minTouch),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TypeTokens.body.copyWith(color: tokens.hibr),
              ),
            ),
            Switch(
              value: value,
              activeThumbColor: tokens.waraq,
              activeTrackColor: tokens.primary,
              inactiveThumbColor: tokens.hibr,
              inactiveTrackColor: tokens.waraq,
              onChanged: (on) => onChanged(on),
            ),
          ],
        ),
      ),
    );
  }
}
