// «عيد المشوار» with its liter (FR-011): on the pause card and the failure
// card. With an empty tank and no unlimited window it fades, says so, and
// does nothing.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/theme/components/secondary_button.dart';
import 'package:wassal/features/trip/presentation/cards/trip_card.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

class RestartButton extends ConsumerWidget {
  const RestartButton({
    required this.enabled,
    required this.onRestart,
    this.buttonKey,
    super.key,
  });

  final bool enabled;
  final VoidCallback onRestart;

  /// On the button itself, for its semantics.
  final Key? buttonKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final numbers = ref.watch(numberFormatterProvider);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          enabled: enabled,
          child: Opacity(
            opacity: enabled ? 1 : 0.55,
            child: SecondaryButton(
              key: buttonKey,
              label: l10n.tripPauseRestart,
              onPressed: enabled ? onRestart : () {},
            ),
          ),
        ),
        CardNote(
          enabled
              ? l10n.tripPauseRestartCost(numbers.integer(-1))
              : l10n.tripPauseRestartEmpty,
        ),
      ],
    );
  }
}
