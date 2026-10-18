import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/app_theme.dart';
import 'package:wassal/core/theme/components/sticker_button.dart';

/// The main action on a screen: أزرق fill with ورق text.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
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
      fill: tokens.primary,
      ink: tokens.waraq,
      expand: expand,
    );
  }
}
