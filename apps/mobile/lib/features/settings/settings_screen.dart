import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/routing/placeholder_screen.dart';
import 'package:wassal/core/routing/routes.dart';
import 'package:wassal/core/theme/components/containers.dart';
import 'package:wassal/core/theme/components/controls.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

/// Settings: still a placeholder, except for the real digit-style control
/// (FR-025).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static Key optionKey(DigitStyle style) =>
      ValueKey('digit-style-${style.wire}');

  @override
  Widget build(BuildContext context) {
    return PlaceholderScreen(
      destination: destinationNamed(RouteNames.settings),
      extra: const _DigitStyleControl(),
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
              onChanged: (style) => unawaited(_choose(ref, style)),
            ),
          ),
        ],
      ),
    );
  }

  /// The row's own side padding, so the control lines up with its title.
  static const double _inset = 14;
}

/// Applies [style] at once and saves it. If the save fails, the choice
/// still holds until the app restarts, and the failure is reported.
Future<void> _choose(WidgetRef ref, DigitStyle style) async {
  try {
    await ref.read(digitStyleProvider.notifier).set(style);
  } on Exception catch (error, stack) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'settings',
        context: ErrorDescription('while saving the digit style'),
      ),
    );
  }
}
