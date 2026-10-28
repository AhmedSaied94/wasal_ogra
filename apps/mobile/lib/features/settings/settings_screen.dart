import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/config/tunable.dart';
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/routing/placeholder_screen.dart';
import 'package:wassal/core/routing/routes.dart';
import 'package:wassal/core/theme/components/containers.dart';
import 'package:wassal/core/theme/components/controls.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/pre_trip/application/card_mode_provider.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

/// Settings: still a placeholder, except for the real digit-style control
/// (FR-025) and the pre-trip card's (specs/013-m08-home-result FR-024;
/// M14 moves both into the `Settings` artboard).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static Key optionKey(DigitStyle style) =>
      ValueKey('digit-style-${style.wire}');

  static Key cardOptionKey(PreTripCardMode mode) =>
      ValueKey('pre-trip-card-${mode.wire}');

  @override
  Widget build(BuildContext context) {
    return PlaceholderScreen(
      destination: destinationNamed(RouteNames.settings),
      extra: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: SpaceTokens.s12,
        children: [_DigitStyleControl(), _PreTripCardControl()],
      ),
    );
  }
}

/// The pre-trip card: a `ListRow` titled «كارت ما قبل المشوار» over a
/// `Segmented`, built like the digit style's.
class _PreTripCardControl extends ConsumerWidget {
  const _PreTripCardControl();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return AppCard(
      padding: const EdgeInsets.only(bottom: _DigitStyleControl._inset),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListRow(title: l10n.settingsPreTripCard),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: _DigitStyleControl._inset,
            ),
            child: Segmented<PreTripCardMode>(
              value: ref.watch(preTripCardModeProvider),
              segmentKey: SettingsScreen.cardOptionKey,
              segments: [
                (PreTripCardMode.always, l10n.settingsPreTripCardAlways),
                (PreTripCardMode.newOnly, l10n.settingsPreTripCardNewOnly),
              ],
              onChanged: (mode) => unawaited(
                _save(
                  () => ref.read(preTripCardModeProvider.notifier).set(mode),
                  'the pre-trip card setting',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The digit style: a `ListRow` titled «شكل الأرقام» over a `primary`
/// `Segmented`, in a card (spec FR-017).
class _DigitStyleControl extends ConsumerWidget {
  const _DigitStyleControl();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return AppCard(
      padding: const EdgeInsets.only(bottom: _inset),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListRow(title: l10n.settingsDigitStyle),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: _inset),
            child: Segmented<DigitStyle>(
              value: ref.watch(digitStyleProvider),
              segmentKey: SettingsScreen.optionKey,
              segments: [
                (DigitStyle.arabicIndic, l10n.digitStyleArabic),
                (DigitStyle.western, l10n.digitStyleWestern),
              ],
              onChanged: (style) => unawaited(
                _save(
                  () => ref.read(digitStyleProvider.notifier).set(style),
                  'the digit style',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The row's own side padding, so the control lines up with its title.
  static const double _inset = 14;
}

/// Applies a choice at once and saves it with [set]. If the save fails,
/// the choice still holds until the app restarts, and the failure is
/// reported as saving [what].
Future<void> _save(Future<void> Function() set, String what) async {
  try {
    await set();
  } on Exception catch (error, stack) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'settings',
        context: ErrorDescription('while saving $what'),
      ),
    );
  }
}
