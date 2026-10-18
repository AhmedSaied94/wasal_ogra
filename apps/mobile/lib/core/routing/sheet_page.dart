import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/app_theme.dart';
import 'package:wassal/core/theme/tokens/shape.dart';

/// A bottom sheet as a router page, so sheets have a name and a URL
/// (research R4). It closes by a drag down, a tap outside, or its close
/// button (FR-018).
class SheetPage<T> extends Page<T> {
  const SheetPage({
    required this.child,
    super.key,
    super.name,
    super.arguments,
  });

  final Widget child;

  @override
  Route<T> createRoute(BuildContext context) {
    final tokens = context.tokens;
    return ModalBottomSheetRoute<T>(
      settings: this,
      builder: (_) => child,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      useSafeArea: true,
      backgroundColor: tokens.waraq,
      barrierLabel: MaterialLocalizations.of(context).scrimLabel,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: tokens.hibr, width: ShapeTokens.borderCard),
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(ShapeTokens.radiusCard),
        ),
      ),
    );
  }
}
