// What opens on arrival at Home (specs/013-m08-home-result, research R9,
// contracts/seams.md `ArrivalItem`): at most one item per arrival, by rank,
// never while one is open or on the arrival that returns from it, and only
// if Home is still on top when the frame ends.
import 'dart:async';

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wassal/core/content/home_arrival.dart';
import 'package:wassal/features/onboarding/presentation/arrival_items.dart';

part 'arrival_queue.g.dart';

abstract interface class ArrivalItem {
  /// Lower opens first: 10 story scene, 20 name sheet, 30 notification ask,
  /// 40 morning piggy.
  int get rank;

  bool isDue(ProviderContainer container);

  /// Opens the item; completes when it is closed or has left Home.
  Future<void> open(BuildContext context, ProviderContainer container);
}

/// Every item, M07's two from the start; M10, M11 and M14 add theirs.
@Riverpod(keepAlive: true)
List<ArrivalItem> arrivalItems(Ref ref) => const [
  DueSceneArrival(),
  NameSheetArrival(),
];

/// Created after `ContentLifecycle`, so on one router notification the pack
/// switch runs first; disposed with it.
final class HomeArrivalQueue {
  HomeArrivalQueue(this._router, this._container) {
    _arrival = HomeArrival(_router, _arrived);
    // Created on Home (a test, or a quick boot): that is an arrival too.
    if (_onHome) _arrived();
  }

  final GoRouter _router;
  final ProviderContainer _container;
  late final HomeArrival _arrival;
  bool _open = false;
  bool _disposed = false;

  bool get _onHome => _router.state.uri.path == HomeArrival.homePath;

  /// Whether an item is open now.
  bool get isOpen => _open;

  void _arrived() {
    // The arrival that returns from an item is part of that item.
    if (_open || _disposed) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_check()));
  }

  Future<void> _check() async {
    if (_open || _disposed || !_onHome) return;
    final items = [..._container.read(arrivalItemsProvider)]
      ..sort((a, b) => a.rank.compareTo(b.rank));
    final due = items.where((item) => item.isDue(_container)).firstOrNull;
    if (due == null) return;
    // The root navigator's: over the bottom nav, as every sheet.
    final context = _router.routerDelegate.navigatorKey.currentContext;
    if (context == null) return;
    _open = true;
    try {
      await due.open(context, _container);
    } on Exception catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(exception: error, stack: stack, library: 'home'),
      );
    } finally {
      _open = false;
    }
  }

  void dispose() {
    _disposed = true;
    _arrival.dispose();
  }
}

/// Completes once [router] has shown [path] and then left it.
Future<void> untilLeft(GoRouter router, String path) {
  final done = Completer<void>();
  var seen = router.state.uri.path == path;
  void changed() {
    final now = router.state.uri.path;
    if (now == path) {
      seen = true;
    } else if (seen && !done.isCompleted) {
      router.routerDelegate.removeListener(changed);
      done.complete();
    }
  }

  router.routerDelegate.addListener(changed);
  return done.future;
}
