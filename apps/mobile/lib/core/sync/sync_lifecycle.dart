// The sync's part of the app's life (specs/011-m06-identity-sync,
// contracts/sync.md "Gates", research R9, R14, R15): the trip route, the
// foreground, the connection, new operations and the account become the
// engine's gates and triggers, a bootstrap runs before the passes that
// follow a start, a return or a reconnection, and the rollback toast is
// shown off the trip screen.
import 'dart:async';

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/account/domain/account.dart';
import 'package:wassal/core/platform/connectivity.dart';
import 'package:wassal/core/routing/routes.dart';
import 'package:wassal/core/sync/bootstrap_service.dart';
import 'package:wassal/core/sync/sync_engine.dart';
import 'package:wassal/core/theme/components/overlays.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

/// Whether [path] is `/trip/:tripId`, the trip screen, with its pause and
/// failure cards over it. The result route isn't.
bool isTripRoute(String path) {
  final segments = Uri.parse(path).pathSegments;
  return segments.length == 2 && segments.first == RouteNames.trip;
}

/// Calls [onChange] when the trip screen starts or stops showing.
final class TripRouteSignal {
  TripRouteSignal(this._router, this._onChange)
    : _shown = isTripRoute(_router.state.uri.path) {
    _router.routerDelegate.addListener(_changed);
  }

  final GoRouter _router;
  final void Function(bool shown) _onChange;
  bool _shown;

  bool get shown => _shown;

  void _changed() {
    final shown = isTripRoute(_router.state.uri.path);
    if (shown == _shown) return;
    _shown = shown;
    _onChange(shown);
  }

  void dispose() => _router.routerDelegate.removeListener(_changed);
}

final class SyncLifecycle {
  SyncLifecycle({
    required GoRouter router,
    required SyncRunner engine,
    required ConnectivitySource connectivity,
    required Stream<int> pendingCounts,
    required int pendingCount,
    required Stream<AccountStatus> statuses,
    required this._status,
    this._bootstrap,
  }) : _router = router,
       _engine = engine,
       _lastPending = pendingCount {
    _route = TripRouteSignal(router, engine.setTripScreen);
    engine.setTripScreen(_route.shown);
    _lifecycle = AppLifecycleListener(
      onResume: () {
        _foreground = true;
        engine.setForeground(true);
        _afterBootstrap(SyncTrigger.resume);
      },
      onHide: _toBackground,
      onPause: _toBackground,
    );
    _subscriptions = [
      connectivity.online.listen((online) {
        if (online) _afterBootstrap(SyncTrigger.online);
      }),
      pendingCounts.listen(_pendingChanged),
      statuses.listen((status) {
        if (status == AccountStatus.active) {
          _afterBootstrap(SyncTrigger.accountActive);
        }
      }),
      engine.events.listen((event) {
        switch (event) {
          case BalanceCorrected():
            _toast();
          // Another player's state: their blocks too, now (R15).
          case StateTaken(why: StateWhy.account):
            unawaited(_bootstrapNow(force: true));
          default:
            break;
        }
      }),
    ];
    _afterBootstrap(SyncTrigger.startup);
  }

  final GoRouter _router;
  final SyncRunner _engine;
  final AccountStatus Function() _status;
  final BootstrapService? _bootstrap;
  bool _foreground = true;
  late final TripRouteSignal _route;
  late final AppLifecycleListener _lifecycle;
  late final List<StreamSubscription<Object?>> _subscriptions;
  int _lastPending;

  void _toBackground() {
    _foreground = false;
    _engine.setForeground(false);
  }

  /// A bootstrap when one is due (R15), then a pass. A failed bootstrap
  /// doesn't hold the pass.
  void _afterBootstrap(SyncTrigger trigger) =>
      unawaited(_bootstrapNow().whenComplete(() => _engine.request(trigger)));

  /// Not for a deleted or absent account, in the background, or with the
  /// trip on screen.
  Future<void> _bootstrapNow({bool force = false}) async {
    final bootstrap = _bootstrap;
    if (bootstrap == null ||
        _status() != AccountStatus.active ||
        !_foreground ||
        _route.shown) {
      return;
    }
    try {
      await bootstrap.refresh(force: force);
    } on Object catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(exception: error, stack: stack, library: 'sync'),
      );
    }
  }

  /// A new operation asks for a (debounced) pass; an answered one doesn't.
  void _pendingChanged(int count) {
    if (count > _lastPending) _engine.request(SyncTrigger.opsRecorded);
    _lastPending = count;
  }

  /// The rollback toast (R14). The engine holds it while the trip screen
  /// shows; this checks again, for a route that changed since.
  void _toast() {
    if (_route.shown) return;
    final navigator = _router.routerDelegate.navigatorKey.currentState;
    final overlay = navigator?.overlay;
    if (navigator == null || overlay == null || !navigator.mounted) return;
    showAppToastOn(
      overlay,
      AppLocalizations.of(navigator.context).syncBalanceCorrected,
    );
  }

  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _lifecycle.dispose();
    _route.dispose();
  }
}
