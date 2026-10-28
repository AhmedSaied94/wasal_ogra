// What opens on arrival at Home (specs/013-m08-home-result, research R9):
// by rank, at most one per arrival, nothing while one is open or on the
// arrival back from it, nothing unless Home is still on top at the frame's
// end, after the pack switch, and never over a trip.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/content/home_arrival.dart';
import 'package:wassal/features/home/application/arrival_queue.dart';

final class _Item implements ArrivalItem {
  _Item(this.rank, this.log, {this.leaveTo});

  @override
  final int rank;
  final List<String> log;

  /// Where opening goes; null opens nothing on the route stack and waits
  /// for [close].
  final String? leaveTo;
  bool due = true;
  bool Function()? dueWhen;
  Completer<void>? _closer;

  void close() => _closer?.complete();

  @override
  bool isDue(ProviderContainer container) => dueWhen?.call() ?? due;

  @override
  Future<void> open(BuildContext context, ProviderContainer container) {
    log.add('open $rank');
    due = false;
    if (leaveTo case final to?) {
      final router = GoRouter.of(context);
      final left = untilLeft(router, to);
      unawaited(router.push<void>(to));
      return left;
    }
    return (_closer = Completer()).future;
  }
}

GoRouter _router() => GoRouter(
  initialLocation: '/start',
  routes: [
    for (final path in ['/start', '/home', '/lines', '/scene', '/trip/x'])
      GoRoute(path: path, builder: (_, _) => Text(path)),
  ],
);

Future<(GoRouter, HomeArrivalQueue)> _pump(
  WidgetTester tester,
  List<ArrivalItem> items, {
  void Function(GoRouter router)? before,
}) async {
  final router = _router();
  final container = ProviderContainer(
    overrides: [arrivalItemsProvider.overrideWithValue(items)],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  before?.call(router);
  final queue = HomeArrivalQueue(router, container);
  addTearDown(queue.dispose);
  addTearDown(router.dispose);
  return (router, queue);
}

Future<void> _go(WidgetTester tester, GoRouter router, String to) async {
  router.go(to);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the first due item by rank, one per arrival', (tester) async {
    final log = <String>[];
    final name = _Item(20, log);
    final scene = _Item(10, log);
    final (router, _) = await _pump(tester, [name, scene]);
    await _go(tester, router, '/home');
    expect(log, ['open 10']);
    scene.close();
    await tester.pumpAndSettle();
    // Closing isn't an arrival.
    expect(log, ['open 10']);

    await _go(tester, router, '/lines');
    await _go(tester, router, '/home');
    expect(log, ['open 10', 'open 20']);
  });

  testWidgets('nothing while one is open, nor on the arrival back from it', (
    tester,
  ) async {
    final log = <String>[];
    final scene = _Item(10, log, leaveTo: '/scene');
    final name = _Item(20, log);
    final (router, queue) = await _pump(tester, [scene, name]);
    await _go(tester, router, '/home');
    expect(log, ['open 10']);
    expect(queue.isOpen, isTrue);

    // The scene goes back to Home: that arrival is the scene's.
    await _go(tester, router, '/home');
    expect(queue.isOpen, isFalse);
    expect(log, ['open 10']);

    await _go(tester, router, '/lines');
    await _go(tester, router, '/home');
    expect(log, ['open 10', 'open 20']);
  });

  testWidgets('nothing unless Home is still on top when the frame ends', (
    tester,
  ) async {
    final log = <String>[];
    var arrivals = 0;
    final (router, _) = await _pump(
      tester,
      [_Item(10, log)],
      // Something leaves Home as soon as it arrives, before the frame ends.
      before: (router) {
        final away = HomeArrival(router, () {
          arrivals++;
          router.go('/lines');
        });
        addTearDown(away.dispose);
      },
    );
    await _go(tester, router, '/home');
    expect(arrivals, 1);
    expect(router.state.uri.path, '/lines');
    expect(log, isEmpty);
  });

  testWidgets('never over a trip; the next arrival at Home', (tester) async {
    final log = <String>[];
    final (router, _) = await _pump(tester, [_Item(10, log)]);
    await _go(tester, router, '/trip/x');
    expect(log, isEmpty);
    await _go(tester, router, '/home');
    expect(log, ['open 10']);
  });

  testWidgets('created on Home: that is an arrival', (tester) async {
    final log = <String>[];
    await _pump(tester, [
      _Item(10, log),
    ], before: (router) => router.go('/home'));
    await tester.pumpAndSettle();
    expect(log, ['open 10']);
  });

  testWidgets("after the pack switch on the same arrival", (tester) async {
    final log = <String>[];
    var switched = false;
    final item = _Item(10, log)..dueWhen = () => switched;
    final (router, _) = await _pump(
      tester,
      [item],
      // ContentLifecycle's arrival is created first.
      before: (router) {
        final content = HomeArrival(router, () => switched = true);
        addTearDown(content.dispose);
      },
    );
    await _go(tester, router, '/home');
    expect(log, ['open 10']);
  });
}
