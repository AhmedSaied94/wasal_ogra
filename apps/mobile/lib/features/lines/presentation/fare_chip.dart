// A line's fare chip, «٨٫٥ ج» (HANDOFF `Lines` block 3b): `ground`, a pill,
// 12/700, from the pack's display fare in piasters.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

class FareChip extends ConsumerWidget {
  const FareChip({required this.farePiasters, this.plain = false, super.key});

  final int farePiasters;

  /// A locked or done card's trailing fare: the text alone, 13/700.
  final bool plain;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = AppLocalizations.of(context)
        .linesFare(ref.watch(numberFormatterProvider).piasters(farePiasters));
    if (plain) return Text(text, style: DesignExtras.linesCardStars);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SpaceTokens.s8,
        vertical: SpaceTokens.s2,
      ),
      decoration: BoxDecoration(
        color: ColorTokens.ground,
        borderRadius: BorderRadius.circular(RadiusTokens.pill),
      ),
      child: Text(
        text,
        style: DesignExtras.linesTileCurrent.copyWith(color: ColorTokens.ink),
      ),
    );
  }
}
