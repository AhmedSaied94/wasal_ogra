import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/routing/placeholder_screen.dart';
import 'package:wassal/core/routing/routes.dart';
import 'package:wassal/core/theme/app_theme.dart';
import 'package:wassal/core/theme/tokens/shape.dart';
import 'package:wassal/core/theme/tokens/space.dart';
import 'package:wassal/core/theme/tokens/typography.dart';
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

class _DigitStyleControl extends ConsumerWidget {
  const _DigitStyleControl();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final current = ref.watch(digitStyleProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.settingsDigitStyle,
          style: TypeTokens.title.copyWith(color: context.tokens.hibr),
        ),
        const SizedBox(height: SpaceTokens.s),
        Row(
          children: [
            for (final (i, style) in DigitStyle.values.indexed) ...[
              if (i > 0) const SizedBox(width: SpaceTokens.s),
              Expanded(
                child: _Option(
                  key: SettingsScreen.optionKey(style),
                  label: switch (style) {
                    DigitStyle.arabicIndic => l10n.digitStyleArabic,
                    DigitStyle.western => l10n.digitStyleWestern,
                  },
                  selected: style == current,
                  onTap: () => unawaited(_choose(ref, style)),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
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

/// One choice of a two-way toggle: أزرق when selected, ورق otherwise.
class _Option extends StatelessWidget {
  const _Option({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: selected ? tokens.primary : tokens.waraq,
            border: Border.all(
              color: tokens.hibr,
              width: ShapeTokens.borderCard,
            ),
            borderRadius: BorderRadius.circular(ShapeTokens.radiusControl),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: ShapeTokens.minTouch),
            child: Padding(
              padding: const EdgeInsets.all(SpaceTokens.s),
              child: Center(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TypeTokens.title.copyWith(
                    color: selected ? tokens.waraq : tokens.hibr,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
