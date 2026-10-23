// «عيد المشوار» with its liter (FR-011): on the pause card and the failure
// card, with the fuel chip «−١» and the fuel icon, never «لتر» (HANDOFF
// §9.1 #4). With an empty tank and no unlimited window it fades, says so,
// and does nothing.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/theme/components/buttons.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/trip/presentation/cards/trip_card.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

class RestartButton extends ConsumerWidget {
  const RestartButton({
    required this.enabled,
    required this.onRestart,
    this.buttonKey,
    this.tile = false,
    super.key,
  });

  final bool enabled;
  final VoidCallback onRestart;

  /// On the button itself, for its semantics.
  final Key? buttonKey;

  /// `Fail`'s `ground` tile instead of `Pause`'s secondary button.
  final bool tile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final numbers = ref.watch(numberFormatterProvider);
    final label = l10n.tripPauseRestart;
    final trailing = enabled
        ? CostChip(amount: l10n.tripFuelChip(numbers.integer(1)))
        : Text(
            l10n.tripPauseRestartEmpty,
            style: DesignExtras.dialogNote.copyWith(color: ColorTokens.ink2),
          );
    final semanticLabel = l10n.pairLabel(
      label,
      enabled
          ? l10n.tripPauseRestartCost(numbers.integer(-1))
          : l10n.tripPauseRestartEmpty,
    );
    if (tile) {
      return CardTile(
        key: buttonKey,
        label: label,
        onTap: onRestart,
        enabled: enabled,
        trailing: trailing,
        semanticLabel: semanticLabel,
        height: DesignExtras.failTileHeight,
        radius: DesignExtras.failTileRadius,
      );
    }
    return AppButton.secondary(
      key: buttonKey,
      label: label,
      onTap: onRestart,
      enabled: enabled,
      trailing: trailing,
      semanticLabel: semanticLabel,
      height: LayoutTokens.buttonH.first,
      radius: DesignExtras.dialogSecondaryRadius,
      labelStyle: DesignExtras.dialogSecondaryLabel,
    );
  }
}
