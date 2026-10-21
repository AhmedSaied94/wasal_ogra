import 'dart:async';

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/content/content_controller.dart';
import 'package:wassal/core/content/content_updater.dart';
import 'package:wassal/core/platform/connectivity.dart';
import 'package:wassal/core/routing/routes.dart';

/// Calls [onArrive] when the location becomes exactly Home's path, coming
/// from anywhere else (specs/006-m04-content-loader/research.md R7). Staying
/// on Home, a sheet over it, a trip or the pause dialog never counts.
final class HomeArrival {
  HomeArrival(this._router, this._onArrive) {
    _last = _path();
    _router.routerDelegate.addListener(_changed);
  }

  static final String homePath = destinationNamed(RouteNames.home).path!;

  final GoRouter _router;
  final VoidCallback _onArrive;
  String? _last;

  String _path() => _router.state.uri.path;

  void _changed() {
    final path = _path();
    if (path == homePath && _last != homePath) _onArrive();
    _last = path;
  }

  void dispose() => _router.routerDelegate.removeListener(_changed);
}

/// Content's part of the app's life, from startup to dispose: the switch at
/// Home, and the update checks on start, resume and reconnection.
final class ContentLifecycle {
  ContentLifecycle({
    required GoRouter router,
    required ContentController controller,
    required ContentUpdater updater,
    required ConnectivitySource connectivity,
  }) : _updater = updater,
       _arrival = HomeArrival(
         router,
         () => _background(controller.switchIfReady()),
       ),
       _lifecycle = AppLifecycleListener(
         onResume: () => _background(updater.onResume()),
         onPause: updater.onBackground,
         onHide: updater.onBackground,
         onDetach: updater.onBackground,
       ) {
    _online = connectivity.online.listen(
      (online) => _background(updater.onConnectivity(online)),
    );
    // The stream reports changes only: start from the current state, so
    // coming back after an offline launch counts as a change.
    _background(connectivity.isOnline().then(updater.onConnectivity));
    _background(updater.start());
  }

  final ContentUpdater _updater;
  final HomeArrival _arrival;
  final AppLifecycleListener _lifecycle;
  late final StreamSubscription<bool> _online;

  void dispose() {
    unawaited(_online.cancel());
    _lifecycle.dispose();
    _arrival.dispose();
    _updater.onBackground();
  }
}

/// Runs content work without awaiting it. It is background work, so an
/// error nothing expected is reported rather than left uncaught.
void _background(Future<void> work) => unawaited(
  work.catchError((Object error, StackTrace stack) {
    FlutterError.reportError(
      FlutterErrorDetails(exception: error, stack: stack, library: 'content'),
    );
  }),
);
