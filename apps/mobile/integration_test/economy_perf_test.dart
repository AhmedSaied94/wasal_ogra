// The economy's device budgets (specs/007-m05-local-economy SC-005,
// quickstart scenario 5). CI doesn't run this. On a mid-range Android
// device:
//
//   fvm flutter drive --flavor dev --profile \
//     --driver=test_driver/integration_test.dart \
//     --target=integration_test/economy_perf_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:content_models/content_models.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wassal/core/config/bundled_config_source.dart';
import 'package:wassal/core/config/config_providers.dart';
import 'package:wassal/core/content/pack_content_source.dart';
import 'package:wassal/core/economy/domain/trusted_time.dart';
import 'package:wassal/core/economy/drift_economy_store.dart';
import 'package:wassal/core/economy/economy.dart';
import 'package:wassal/core/economy/economy_service.dart';
import 'package:wassal/core/economy/trusted_clock.dart';
import 'package:wassal/core/platform/uptime.dart';
import 'package:wassal/core/storage/app_database.dart';
import 'package:wassal/core/storage/connection.dart';

import '../test/helpers/content.dart' show sampleBundledFileAsset;
import '../test/helpers/economy.dart' show seedOps, testEpochMs, tripResult;

const _ops = 50000;
const _rounds = 20;

int _median(List<int> times) => ([...times]..sort())[times.length ~/ 2];

/// The milliseconds [body] takes.
Future<int> _time(Future<void> Function() body) async {
  final watch = Stopwatch()..start();
  await body();
  return watch.elapsedMilliseconds;
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the economy within the device budgets', (tester) async {
    final medians = await tester.runAsync(() async {
      // The dev flavor bundles the sample; the host's files aren't here.
      final pack = await rootBundle.load(sampleBundledFileAsset);
      final content = PackContentSource(
        Pack.fromJson(
          (jsonDecode(
            utf8.decode(gzip.decode(Uint8List.sublistView(pack))),
          ) as Map<String, dynamic>).cast<String, Object?>(),
        ),
      );
      final tunables = BundledConfigSource(
        (jsonDecode(
          await rootBundle.loadString(bundledTunablesAsset),
        ) as Map<String, dynamic>).cast<String, Object?>(),
      );

      final dir = Directory(
        '${(await getTemporaryDirectory()).path}/economy_perf',
      );
      if (dir.existsSync()) dir.deleteSync(recursive: true);
      dir.createSync(recursive: true);
      final file = File('${dir.path}/$databaseFileName');
      final seeding = AppDatabase(
        NativeDatabase(file, setup: configureConnection),
        firstOpen: () => FirstOpen(
          state: EconomyState.newPlayer(fuelMax: 5, nowMs: testEpochMs),
          anchor: firstAnchor(null, testEpochMs),
        ),
      );
      await seedOps(
        seeding,
        DriftEconomyStore(seeding),
        count: _ops,
        bonat: 1000,
        content: content,
      );
      await seeding.close();

      // Open + load, as startup does, after one warm-up.
      final opens = <int>[];
      for (var run = 0; run < 6; run++) {
        late AppDatabase db;
        final ms = await _time(() async {
          db = AppDatabase(openDatabaseFile(file));
          await db.customSelect('SELECT 1').get();
          await DriftEconomyStore(db).load();
        });
        await db.close();
        if (run > 0) opens.add(ms);
      }

      // Each kind of op, through the service, on the 50,000-op file.
      final db = AppDatabase(openDatabaseFile(file));
      final store = DriftEconomyStore(db);
      const uptime = ChannelUptimeSource();
      final clock = await UptimeTrustedClock.open(
        uptime: uptime,
        device: DateTime.now,
        store: store,
        snapshot: await uptime.snapshot(),
      );
      final economy = await EconomyService.open(
        store: store,
        clock: clock,
        content: () => content,
        contentVersion: () => content.version,
        tunables: () => tunables,
      );
      final times = <String, List<int>>{};
      Future<void> timed(String kind, Future<OpOutcome> Function() op) async {
        late OpOutcome outcome;
        final ms = await _time(() async => outcome = await op());
        expect(outcome, isA<OpApplied>(), reason: kind);
        (times[kind] ??= []).add(ms);
      }

      for (var i = 0; i < _rounds; i++) {
        final start = economy.newRequestId();
        await timed(
          'trip_start',
          () => economy.startTrip(start, tripId: 'line_hay.01'),
        );
        await timed(
          'spend_bonat',
          () => economy.buy(
            economy.newRequestId(),
            kind: SkuKind.booster,
            skuId: 'change_bag',
          ),
        );
        await timed(
          'use_booster',
          () => economy.useBooster(
            economy.newRequestId(),
            booster: BoosterId.changeBag,
          ),
        );
        await timed(
          'ad_reward',
          () => economy.applyAdReward(
            economy.newRequestId(),
            placement: AdPlacement.trafficJam,
          ),
        );
        await timed(
          'trip_result',
          () => economy.recordResult(
            economy.newRequestId(),
            start: start,
            result: tripResult(tripId: 'line_hay.01'),
          ),
        );
      }
      // The sample sells four things for JENEHAT, each once.
      for (final (kind, skuId, variantId) in [
        (SkuKind.item, 'salon.nish', 'classic'),
        (SkuKind.item, 'salon.sitara', 'plain'),
        (SkuKind.vehicle, 'micro_old', null),
        (SkuKind.chapter, 'ch3_shabka', null),
      ]) {
        await timed(
          'spend_jenehat',
          () => economy.buy(
            economy.newRequestId(),
            kind: kind,
            skuId: skuId,
            variantId: variantId,
          ),
        );
      }
      economy.dispose();
      await db.close();
      dir.deleteSync(recursive: true);

      return {
        'open_load_ms': _median(opens),
        for (final MapEntry(:key, :value) in times.entries)
          '${key}_ms': _median(value),
      };
    });

    binding.reportData = medians;
    // ignore: avoid_print
    print('economy medians: $medians');
    expect(medians!['open_load_ms'], inInclusiveRange(0, 200));
    for (final MapEntry(:key, :value) in medians.entries) {
      if (key == 'open_load_ms') continue;
      expect(value, inInclusiveRange(0, 100), reason: key);
    }
  });
}
