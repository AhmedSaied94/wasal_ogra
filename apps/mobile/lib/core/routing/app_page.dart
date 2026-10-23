import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';

/// A full-screen page with a short fade-through (M03 FR-022). With the
/// phone's reduce-motion setting on it is a plain fade, with no scale or
/// slide (M03 FR-023), of at most 150 ms.
class AppPage<T> extends CustomTransitionPage<T> {
  const AppPage({
    required super.child,
    required bool reduceMotion,
    super.key,
    super.name,
    super.arguments,
  }) : super(
         transitionDuration: reduceMotion
             ? DesignExtras.reducedFade
             : DesignExtras.pageTransition,
         reverseTransitionDuration: reduceMotion
             ? DesignExtras.reducedFade
             : DesignExtras.pageTransition,
         transitionsBuilder: _transition,
       );

  static final _enter = CurveTween(curve: DesignExtras.pageEnterCurve);
  static final _exit = CurveTween(curve: DesignExtras.pageExitCurve);
  static final _grow = Tween<double>(
    begin: DesignExtras.pageGrowFrom,
    end: 1,
  ).chain(_enter);

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
