import 'dart:async';

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// The one way placeholder links navigate, so a double tap or a tap on a
/// page that is already covered never stacks extra routes (FR-024).
///
/// A request is dropped when:
/// - another request was made and the router has not drawn it yet;
/// - the target is the current location; or
/// - the caller's page is no longer on top (it is covered or leaving).
///
/// Each method returns whether it navigated.
abstract final class NavGuard {
  static bool _pending = false;

  static bool go(BuildContext context, String location) =>
      _run(context, location, (router) => router.go(location));

  static bool push(BuildContext context, String location) =>
      _run(context, location, (router) => unawaited(router.push(location)));

  /// Replaces the top page, for hand-offs that should not come back on back:
  /// the pre-trip sheet to the trip, and the trip to its result.
  static bool pushReplacement(BuildContext context, String location) => _run(
    context,
    location,
    (router) => unawaited(router.pushReplacement(location)),
  );

  static bool _run(
    BuildContext context,
    String location,
    void Function(GoRouter router) navigate,
  ) {
    final router = GoRouter.of(context);
    // The top route's location; the router's own URI leaves out pushes.
    final current = router.state.uri.toString();
    if (_pending || current == location || !_isOnTop(context)) return false;
    _pending = true;
    // The router applies the change on the next frame; after it, the
    // caller's page is covered and [_isOnTop] takes over.
    WidgetsBinding.instance.addPostFrameCallback((_) => _pending = false);
    navigate(router);
    return true;
  }

  /// Whether [context]'s route is the current one in its navigator, and so
  /// on up through every enclosing navigator (a tab inside the shell).
  static bool _isOnTop(BuildContext context) {
    BuildContext? at = context;
    while (at != null) {
      final route = ModalRoute.of(at);
      if (route == null) return true;
      if (!route.isCurrent) return false;
      at = route.navigator?.context;
    }
    return true;
  }
}
