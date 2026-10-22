import 'package:material_ui/material_ui.dart';

/// Back on the trip never leaves it (FR-020): [onBack] decides, and the
/// trip screen pauses (the `tripPause` destination, an overlay with no URL)
/// or closes the pause again.
class TripBackGuard extends StatelessWidget {
  const TripBackGuard({required this.onBack, required this.child, super.key});

  final VoidCallback onBack;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) onBack();
      },
      child: child,
    );
  }
}
