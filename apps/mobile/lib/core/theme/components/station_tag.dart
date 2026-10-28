// A station's colour and letter (HANDOFF §3.4 `StationTag`), so colour is
// never the only cue (constitution XI). The trip puts one on each
// passenger's shoulder; the pre-trip card puts one in each price cell
// (specs/013-m08-home-result, research R25).
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

/// The letter of a stop's [slot] (0–3) in drop-off order: أ ب ج د.
String stationLetterOf(AppLocalizations l10n, int slot) => switch (slot % 4) {
  0 => l10n.tripStationLetter1,
  1 => l10n.tripStationLetter2,
  2 => l10n.tripStationLetter3,
  _ => l10n.tripStationLetter4,
};

/// A station tag: 24 on the back row, 26 in the middle, 30 near. [hot]
/// rings it in `danger`; the trip makes it beat on its own clock.
class StationTag extends StatelessWidget {
  const StationTag({
    required this.slot,
    required this.size,
    this.hot = false,
    this.bordered = true,
    super.key,
  });

  /// Its stop's place in drop-off order: the colour and the letter أ ب ج د.
  final int slot;
  final double size;
  final bool hot;

  /// The paper border and lip it wears on a passenger; the price cells'
  /// tags (`PreTrip` box 16) are flat.
  final bool bordered;

  double get _letter => switch (size) {
    <= 24 => DesignExtras.tagLetterBack,
    <= 26 => DesignExtras.tagLetterMiddle,
    _ => DesignExtras.tagLetterNear,
  };

  @override
  Widget build(BuildContext context) {
    final colors = StationColors.all[slot % StationColors.all.length];
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.bg,
          shape: BoxShape.circle,
          border: bordered
              ? Border.all(
                  color: ColorTokens.paper,
                  width: DesignExtras.tagBorder,
                  strokeAlign: BorderSide.strokeAlignInside,
                )
              : null,
          boxShadow: [
            if (hot)
              RingTokens.hot.spread
            else if (bordered)
              DesignExtras.tagLip,
          ],
        ),
        child: Center(
          child: Text(
            stationLetterOf(AppLocalizations.of(context), slot),
            style: TypeTokens.label
                .weight(700)
                .copyWith(color: colors.letter, fontSize: _letter, height: 1),
          ),
        ),
      ),
    );
  }
}
