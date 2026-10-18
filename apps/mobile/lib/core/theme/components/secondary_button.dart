import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/app_theme.dart';
import 'package:wassal/core/theme/components/sticker_button.dart';

/// A secondary action: ورق fill with حبر text.
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    required this.label,
    required this.onPressed,
    this.expand = true,
    super.key,
  });

  final String label;
  final VoidCallback onPressed;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return StickerButton(
      label: label,
      onPressed: onPressed,
      fill: tokens.waraq,
      ink: tokens.hibr,
      expand: expand,
    );
  }
}
