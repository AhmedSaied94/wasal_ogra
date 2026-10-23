import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';

import '../boxes.dart';
import 'board.dart';

// The `Tokens` board as the app's tokens draw it (contracts/design-checks.md
// "Surfaces"): every swatch in its token's colour, every type sample in its
// TypeTokens style, at the board's places. 1200×1220, no taps.

/// The type samples' styles by the name in the label beside each.
const _typeByName = {
  'display.xl': TypeTokens.displayXl,
  'display.l': TypeTokens.displayL,
  'button.xl': TypeTokens.buttonXl,
  'display.m': TypeTokens.displayM,
  'button.l': TypeTokens.buttonL,
  'display.s': TypeTokens.displayS,
  'quote': TypeTokens.quote,
  'number.l': TypeTokens.numberL,
  'bubble': TypeTokens.bubble,
  'row': TypeTokens.row,
  'body': TypeTokens.body,
  'caption': TypeTokens.caption,
  'label': TypeTokens.label,
};

class TokensSample extends StatelessWidget {
  const TokensSample({required this.board, required this.digits, super.key});

  final DesignBoard board;
  final DigitStyle digits;

  static const size = Size(1200, 1220);

  /// The type panel (`Tokens` box 121): each sample is followed by its
  /// label, «`name` · …».
  static const _typePanel = 121;

  TextStyle? _typeStyle(DesignBox b) {
    if (b.parent != _typePanel || b.color?.endsWith('ink.2') == true) {
      return null;
    }
    final i = board.boxes.indexOf(b);
    final label = board.boxes[i + 1].text ?? '';
    final style = _typeByName[label.split(' ·').first.split(' ').first];
    return style?.copyWith(
      color: b.color == null ? ColorTokens.ink : boxColor(b.color!),
    );
  }

  @override
  Widget build(BuildContext context) => SizedBox.fromSize(
    size: size,
    child: ColoredBox(
      color: ColorTokens.paper,
      child: Stack(
        children: [
          for (final b in board.boxes)
            if (b.parent != null) boardBox(b, digits, style: _typeStyle(b)),
        ],
      ),
    ),
  );
}
