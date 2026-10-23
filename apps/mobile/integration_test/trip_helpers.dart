// What the trip's device tests share: the app on its real database and
// clock, with no network.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/core/content/content_providers.dart';
import 'package:wassal/core/platform/connectivity.dart';
import 'package:wassal/core/storage/connection.dart';
import 'package:wassal/features/trip/application/trip_controller.dart';
import 'package:wassal/features/trip/trip_providers.dart';

import '../test/helpers/content.dart';
import '../test/helpers/pump_app.dart';

/// No network, whatever the device has.
final _offline = [
  contentRemoteProvider.overrideWithValue(FakeContentRemote()),
  connectivitySourceProvider.overrideWithValue(FakeConnectivitySource()),
];

/// Deletes the app's database file: a fresh install.
Future<void> deleteAppDatabase() async {
  final file = await appDatabaseFile();
  for (final suffix in ['', '-wal', '-shm']) {
    final part = File('${file.path}$suffix');
    if (part.existsSync()) part.deleteSync();
  }
}

/// Pumps frames in real time until [done].
Future<void> pumpUntil(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 200 && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
  }
  expect(done(), isTrue);
}

/// Pumps the app with the real economy and [fixture]'s seed, and waits
/// until boot has handed off to [landing].
Future<ProviderContainer> launchOffline(
  WidgetTester tester,
  ParityFixture fixture, {
  String landing = '/home',
}) async {
  final container = await pumpWassalApp(
    tester,
    content: _offline,
    economy: const [],
    settle: false,
    overrides: [
      tripFixedProvider.overrideWithValue(
        FixedTrip(
          definition: fixture.definition,
          params: fixture.params,
          seed: fixture.seed,
        ),
      ),
    ],
  );
  await pumpUntil(tester, () => currentLocation(tester) == landing);
  return container;
}

/// Disposes the scope, as a process exit does, and lets the file close.
Future<void> quitApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 500)),
  );
}
