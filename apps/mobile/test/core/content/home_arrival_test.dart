import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/content/content_controller.dart';
import 'package:wassal/core/content/content_providers.dart';
import 'package:wassal/core/content/content_updater.dart';
import 'package:wassal/core/content/decode_pack_file.dart';
import 'package:wassal/core/content/pack_store.dart';
import 'package:wassal/core/routing/router.dart';
import 'package:wassal/features/trip/application/trip_phase.dart';
import 'package:wassal/features/trip/presentation/cards/pause_card.dart';

import '../../helpers/content.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/trip.dart';

// The switch happens only on arrival at Home (contracts/updates.md "The
// switch at Home", FR-024 to FR-027).

/// Stores v2 as ready and hands the controller its decoded pack, as a
/// finished download does.
void _readyV2(ProviderContainer container) {
  storeSampleVersion(container.read(packStoreProvider).requireValue, 2);
  final pack = samplePackVersion(2);
  final decoded = decodePackFile(pack.bytes, pack.expected) as PackDecoded;
  container.read(activeContentProvider.notifier).acceptReady(decoded.source);
}

Future<void> _go(WidgetTester tester, ProviderContainer c, String to) async {
  c.read(routerProvider).go(to);
  await tester.pumpAndSettle();
}

int _version(ProviderContainer container) =>
    container.read(contentVersionProvider);

void main() {
  testWidgets('going to Home switches to the ready pack', (tester) async {
    final container = await pumpWassalApp(tester);
    await _go(tester, container, '/lines');
    _readyV2(container);
    expect(_version(container), 1);

    await _go(tester, container, '/home');
    expect(_version(container), 2);
    expect(
      container.read(activeContentProvider).requireValue.origin,
      ContentOrigin.stored,
    );
  });

  testWidgets('no other screen switches', (tester) async {
    final container = await pumpWassalApp(tester);
    await _go(tester, container, '/lines');
    _readyV2(container);
    for (final location in [
      '/home/pre-trip/line_hay.01',
      '/trip/line_hay.01',
      '/trip/line_hay.01/result',
      '/shop/fuel',
    ]) {
      await _go(tester, container, location);
      expect(_version(container), 1, reason: location);
    }
  });

  testWidgets('a pack that gets ready on Home waits for the next arrival', (
    tester,
  ) async {
    final container = await pumpWassalApp(tester);
    expect(currentLocation(tester), '/home');
    _readyV2(container);
    await tester.pumpAndSettle();
    expect(_version(container), 1);

    await _go(tester, container, '/lines');
    expect(_version(container), 1);
    await _go(tester, container, '/home');
    expect(_version(container), 2);
  });

  testWidgets('the trip pause never switches', (tester) async {
    final container = await pumpWassalApp(tester);
    await _go(tester, container, '/trip/line_hay.01');
    _readyV2(container);

    controllerOf(tester).pause(PauseReason.button);
    await tester.pumpAndSettle();
    expect(find.byType(PauseCard), findsOneWidget);
    expect(_version(container), 1);

    await tester.tap(find.text('كمّل المشوار'));
    await tester.pumpAndSettle();
    expect(find.byType(PauseCard), findsNothing);
    expect(_version(container), 1);
  });

  testWidgets('after an offline launch, the connection coming back checks', (
    tester,
  ) async {
    final remote = FakeContentRemote();
    final connectivity = FakeConnectivitySource()..current = false;
    final clock = FakeClock(DateTime.utc(2026, 10, 21, 9));
    await pumpWassalApp(
      tester,
      content: contentTestOverrides(
        remote: remote,
        connectivity: connectivity,
        clock: clock.call,
      ),
    );
    await tester.pumpAndSettle();
    expect(remote.manifestRequests, 1);

    clock.advance(ContentUpdater.throttle);
    // The stream's first event: no change was ever reported before it.
    connectivity.set(true);
    await tester.pumpAndSettle();
    expect(remote.manifestRequests, 2);
  });

  testWidgets('the updater waits for startup', (tester) async {
    final remote = FakeContentRemote();
    final gate = Completer<void>();
    await pumpWassalApp(
      tester,
      content: contentTestOverrides(
        remote: remote,
        decoder: (bytes, expected) async {
          await gate.future;
          return decodePackFile(bytes, expected);
        },
      ),
    );
    expect(currentLocation(tester), '/boot');
    expect(remote.manifestRequests, 0);

    gate.complete();
    await tester.pumpAndSettle();
    expect(currentLocation(tester), '/home');
    expect(remote.manifestRequests, 1);
  });
}
