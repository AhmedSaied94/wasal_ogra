import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/content/content_controller.dart';
import 'package:wassal/core/content/decode_pack_file.dart';
import 'package:wassal/core/content/pack_store.dart';
import 'package:wassal/core/economy/domain/trusted_time.dart';
import 'package:wassal/core/economy/economy.dart';
import 'package:wassal/core/economy/economy_providers.dart';
import 'package:wassal/core/platform/uptime.dart';
import 'package:wassal/features/boot/boot_screen.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

import '../helpers/content.dart';
import '../helpers/economy.dart';
import '../helpers/pump_app.dart';

// The economy joins startup (FR-005): the boot screen waits for it, a
// failure shows the retry, and the retry opens everything again.

final _l10n = lookupAppLocalizations(const Locale('ar'));

/// An uptime source whose first reading fails.
final class _FailingOnce implements UptimeSource {
  final _uptime = FakeUptimeSource();
  bool _failed = false;

  @override
  Future<BootSnapshot?> snapshot() async {
    if (!_failed) {
      _failed = true;
      throw StateError('no reading');
    }
    return _uptime.snapshot();
  }
}

void main() {
  testWidgets('the boot screen waits for the economy, then hands over', (
    tester,
  ) async {
    final gate = Completer<void>();
    await pumpWassalApp(
      tester,
      economy: [
        uptimeSourceProvider.overrideWithValue(FakeUptimeSource()),
        databaseOpenerProvider.overrideWithValue(() async {
          await gate.future;
          return NativeDatabase.memory();
        }),
      ],
    );
    expect(currentLocation(tester), '/boot');
    expect(find.byType(BootScreen), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();
    expect(currentLocation(tester), '/home');
  });

  testWidgets('a database that fails to open shows the retry, never Home', (
    tester,
  ) async {
    var opens = 0;
    await pumpWassalApp(
      tester,
      economy: [
        uptimeSourceProvider.overrideWithValue(FakeUptimeSource()),
        databaseOpenerProvider.overrideWithValue(() async {
          if (opens++ == 0) throw StateError('disk unreadable');
          return NativeDatabase.memory();
        }),
      ],
    );
    expect(currentLocation(tester), '/boot');
    expect(find.text(_l10n.bootErrorMessage), findsOneWidget);
    expect(find.text(_l10n.bootRetry), findsOneWidget);

    await tester.tap(find.text(_l10n.bootRetry));
    await tester.pumpAndSettle();
    expect(opens, 2);
    expect(currentLocation(tester), '/home');
  });

  testWidgets('an uptime reading that fails shows the retry, which recovers', (
    tester,
  ) async {
    await pumpWassalApp(
      tester,
      economy: [
        uptimeSourceProvider.overrideWithValue(_FailingOnce()),
        databaseOpenerProvider.overrideWithValue(
          () async => NativeDatabase.memory(),
        ),
      ],
    );
    expect(currentLocation(tester), '/boot');
    expect(find.text(_l10n.bootRetry), findsOneWidget);

    await tester.tap(find.text(_l10n.bootRetry));
    await tester.pumpAndSettle();
    expect(currentLocation(tester), '/home');
  });

  testWidgets('after boot the economy view reads synchronously', (
    tester,
  ) async {
    final container = await pumpWassalApp(tester);
    final view = container.read(economyViewProvider);
    expect(view.jenehat, 0);
    expect(view.fuel.liters, view.fuel.max);
  });

  testWidgets('a content switch at Home keeps the same economy', (
    tester,
  ) async {
    final container = await pumpWassalApp(tester);
    final economy = container.read(economyProvider).requireValue;
    final db = container.read(appDatabaseProvider).requireValue;

    // What the updater leaves, then arrival at Home (M04 research R7).
    storeSampleVersion(await container.read(packStoreProvider.future), 3);
    final pack = samplePackVersion(3);
    final decoded = decodePackFile(pack.bytes, pack.expected) as PackDecoded;
    final controller = container.read(activeContentProvider.notifier)
      ..acceptReady(decoded.source);
    await tester.runAsync(controller.switchIfReady);
    await tester.pumpAndSettle();

    expect(container.read(activeContentProvider).requireValue.version, 3);
    expect(container.read(economyProvider).requireValue, same(economy));
    expect(container.read(appDatabaseProvider).requireValue, same(db));

    // The same service goes on, on the new pack, and the view follows it.
    final outcome = await tester.runAsync(
      () => economy.startTrip(economy.newRequestId(), tripId: 'line_hay.01'),
    );
    expect((outcome! as OpApplied).op.op.contentVersion, 3);
    await tester.pump();
    final view = container.read(economyViewProvider);
    expect(view.fuel.liters, view.fuel.max - 1);
  });
}
