// The height a Lines sheet is drawn at (specs/014-m09-lines-vehicles,
// `LineDetails` block 2, `BuyVehicle` block 2): its top a fixed distance
// below the screen's, its button pinned at the bottom, however little it
// holds. On a shorter screen it takes what there is and scrolls.
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/components/containers.dart';

class BoardSheet extends StatelessWidget {
  const BoardSheet({required this.top, required this.child, super.key});

  /// The sheet's top on the 844-high board, which draws a 36 status bar.
  final double top;
  final Widget child;

  /// The board's status bar.
  static const double _boardInset = 36;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      // The sheet may reach the screen's top inset; drawn, it stops [top]
      // below the board's.
      final lower = top - _boardInset - (screenTopInset(context) - _boardInset);
      final height = (box.maxHeight - lower).clamp(0.0, box.maxHeight);
      return SizedBox(height: height, child: child);
    },
  );
}
