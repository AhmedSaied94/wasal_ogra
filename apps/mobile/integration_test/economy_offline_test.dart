// The economy offline on a real device (specs/007-m05-local-economy SC-007,
// quickstart scenario 3): the real `wassal/clock` channel and the real
// database file, with no network. CI doesn't run this. On a device in
// airplane mode:
//
//   fvm flutter test integration_test/economy_offline_test.dart --flavor dev
import 'dart:io';

import 'package:content_models/content_models.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wassal/core/content/content_providers.dart';
import 'package:wassal/core/economy/economy.dart';
import 'package:wassal/core/economy/economy_providers.dart';
import 'package:wassal/core/economy/economy_service.dart';
import 'package:wassal/core/platform/connectivity.dart';
import 'package:wassal/core/storage/connection.dart';

import '../test/helpers/content.dart';
import '../test/helpers/economy.dart' show tripResult;
import '../test/helpers/pump_app.dart';

/// No network, whatever the device has.
final _offline = [
  contentRemoteProvider.overrideWithValue(FakeContentRemote()),
  connectivitySourceProvider.overrideWithValue(FakeConnectivitySource()),
];

/// Pumps the app with the real economy, and waits for الموقف.
Future<ProviderContainer> _launch(WidgetTester tester) async {
  final container = await pumpWassalApp(
    tester,
    content: _offline,
    economy: const [],
  );
  for (var i = 0; i < 100 && currentLocation(tester) != '/home'; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
  }
  expect(currentLocation(tester), '/home');
  return container;
}

/// Disposes the scope, as a process exit does, and lets the file close.
Future<void> _quit(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 500)),
  );
}

Future<T> _run<T>(WidgetTester tester, Future<T> Function() body) async =>
    (await tester.runAsync(body)) as T;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('earn, buy, restart: everything is still there', (tester) async {
    // A fresh install: no file yet. Only this test deletes it.
    await _run(tester, () async {
      final file = await appDatabaseFile();
      for (final suffix in ['', '-wal', '-shm']) {
        final part = File('${file.path}$suffix');
        if (part.existsSync()) part.deleteSync();
      }
    });

    var container = await _launch(tester);
    var view = container.read(economyViewProvider);
    expect(view.fuel.liters, view.fuel.max);
    expect(view.jenehat, 0);
    final max = view.fuel.max;

    final economy = await _run<EconomyService>(
      tester,
      () => container.read(economyProvider.future),
    );

    /// A finished line_gamaa.02 paying 50, of the 60 it may.
    Future<void> play() => _run(tester, () async {
      final start = economy.newRequestId();
      expect(
        await economy.startTrip(start, tripId: 'line_gamaa.02'),
        isA<OpApplied>(),
      );
      expect(
        await economy.recordResult(
          economy.newRequestId(),
          start: start,
          result: tripResult(tripId: 'line_gamaa.02', earnings: 50),
        ),
        isA<OpApplied>(),
      );
    });

    await play();
    view = economy.view;
    expect(view.fuel.liters, max - 1);
    expect(view.jenehat, 50);
    expect(view.progress['line_gamaa.02']?.plays, 1);

    // salon.sitara costs 150.
    await play();
    await play();
    final sitara = container.read(contentSourceProvider).item('salon.sitara')!;
    final variant = sitara.variants.first.variantId;
    expect(
      await _run(
        tester,
        () => economy.buy(
          economy.newRequestId(),
          kind: SkuKind.item,
          skuId: 'salon.sitara',
          variantId: variant,
        ),
      ),
      isA<OpApplied>(),
    );
    view = economy.view;
    expect(view.jenehat, 0);
    expect(view.fuel.liters, max - 3);
    expect(view.variantOf('salon.sitara'), variant);

    await _quit(tester);
    container = await _launch(tester);
    final after = container.read(economyViewProvider);
    expect(after.jenehat, 0);
    // Seconds passed, not the 20 minutes a liter takes.
    expect(after.fuel.liters, max - 3);
    expect(after.fuel.nextLiterAtMs, view.fuel.nextLiterAtMs);
    expect(after.progress['line_gamaa.02']?.plays, 3);
    expect(after.progress['line_gamaa.02']?.bestStars, 3);
    expect(after.variantOf('salon.sitara'), variant);
    expect(after.unfinished, isNull);
    expect(after.lastResult?.earningsJenehat, 50);
  });
}
