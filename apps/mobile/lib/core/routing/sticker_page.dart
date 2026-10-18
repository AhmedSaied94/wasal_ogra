import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/tokens/motion.dart';

/// A full-screen page with a short fade-through (FR-022). With the phone's
/// reduce-motion setting on it is a plain fade, with no scale or slide
/// (FR-023), lasting `fast`.
class StickerPage<T> extends CustomTransitionPage<T> {
  const StickerPage({
    required super.child,
    required bool reduceMotion,
    super.key,
    super.name,
    super.arguments,
  }) : super(
         transitionDuration: reduceMotion
             ? MotionTokens.fast
             : MotionTokens.screen,
         reverseTransitionDuration: reduceMotion
             ? MotionTokens.fast
             : MotionTokens.screen,
         transitionsBuilder: _transition,
       );

  static final _enter = CurveTween(
    curve: const Interval(0.3, 1, curve: Curves.easeOut),
  );
  static final _exit = CurveTween(
    curve: const Interval(0, 0.3, curve: Curves.easeIn),
  );
  static final _grow = Tween<double>(begin: 0.92, end: 1).chain(_enter);

  /// The incoming page fades in and grows slightly after the outgoing page
  /// has mostly faded out. `drive` adds no listeners of its own, so nothing
  /// needs disposing.
  static Widget _transition(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // Read on every build, so the setting applies as soon as it changes.
    if (MediaQuery.disableAnimationsOf(context)) {
      return FadeTransition(opacity: animation, child: child);
    }
    return FadeTransition(
      opacity: ReverseAnimation(secondaryAnimation.drive(_exit)),
      child: FadeTransition(
        opacity: animation.drive(_enter),
        child: ScaleTransition(scale: animation.drive(_grow), child: child),
      ),
    );
  }
}
