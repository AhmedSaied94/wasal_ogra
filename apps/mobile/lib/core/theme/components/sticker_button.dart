import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/app_theme.dart';
import 'package:wassal/core/theme/tokens/shape.dart';
import 'package:wassal/core/theme/tokens/space.dart';
import 'package:wassal/core/theme/tokens/typography.dart';

/// Minimum button height in points (contracts/design-tokens.md).
const double stickerButtonMinHeight = 52;

/// The shared body of [PrimaryButton] and [SecondaryButton]: a bordered
/// sticker with a hard shadow. Pressing drops the shadow and moves the
/// button onto it, as if pushed into the page.
class StickerButton extends StatefulWidget {
  const StickerButton({
    required this.label,
    required this.onPressed,
    required this.fill,
    required this.ink,
    this.expand = true,
    super.key,
  });

  final String label;
  final VoidCallback onPressed;
  final Color fill;
  final Color ink;

  /// Fills the available width when true (the default).
  final bool expand;

  @override
  State<StickerButton> createState() => _StickerButtonState();
}

class _StickerButtonState extends State<StickerButton> {
  bool _pressed = false;

  void _setPressed(bool pressed) {
    if (_pressed != pressed) setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final shadow = hardShadowOffset(
      ShapeTokens.shadowPrimary,
      Directionality.of(context),
    );
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        onTap: widget.onPressed,
        child: Transform.translate(
          offset: _pressed ? shadow : Offset.zero,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: widget.fill,
              border: Border.all(
                color: tokens.hibr,
                width: ShapeTokens.borderCard,
              ),
              borderRadius: BorderRadius.circular(ShapeTokens.radiusControl),
              boxShadow: _pressed
                  ? const []
                  : [BoxShadow(color: tokens.hibr, offset: shadow)],
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: stickerButtonMinHeight,
                minWidth: widget.expand ? double.infinity : 0,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: SpaceTokens.xl,
                  vertical: SpaceTokens.s,
                ),
                child: Center(
                  widthFactor: widget.expand ? null : 1,
                  heightFactor: 1,
                  child: Text(
                    widget.label,
                    textAlign: TextAlign.center,
                    style: TypeTokens.button.copyWith(color: widget.ink),
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
