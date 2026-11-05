import 'package:content_models/content_models.dart';
import 'package:drift/drift.dart' show DatabaseConnectionUser;
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/economy/domain/rules.dart';
import 'package:wassal/core/economy/drift_economy_store.dart';
import 'package:wassal/core/storage/app_database.dart';

import '../../helpers/economy.dart';
import '../../helpers/older_schema.dart';

// Schema v6 (specs/018-m11-ads/data-model.md "Drift schema 6", T013): the
// log's `ad_reward_seen`, the trip outbox's `ad_reward` kind and
// `server_info.ads`. The generated migration test checks the shapes; these
// check the rows.

Future<List<Map<String, Object?>>> _rows(
  DatabaseConnectionUser db,
  String table,
) async => [
  for (final r in await db.customSelect('SELECT * FROM $table').get()) r.data,
];

Future<void> _insertOp(DatabaseConnectionUser db, String type, int n) =>
    db.customStatement(
      'INSERT INTO ledger_ops (txn_id, op_type, payload, occurred_at_ms, '
      'content_version, fuel_max, fuel_regen_minutes) VALUES '
      "('0192f3a1-7b2c-7d4e-8f00-${n.toRadixString(16).padLeft(12, '0')}', "
      "'$type', '{}', 1, 1, 5, 20)",
    );

Future<void> _insertIntent(DatabaseConnectionUser db, String kind) =>
    db.customStatement(
      'INSERT INTO trip_intent (request_txn, start_txn, kind, booster) '
      "VALUES ('r-$kind', 's-1', '$kind', 'traffic_jam')",
    );

void main() {
  test('v5 refuses the two new kinds', () async {
    final v5 = await olderSchemas.schemaAt(5);
    final db = AppDatabase(v5.newConnection());
    addTearDown(db.close);
    // The raw v5 file, without the upgrade.
    final raw = v5.rawDatabase;
    expect(
      () => raw.execute(
        'INSERT INTO ledger_ops (txn_id, op_type, payload, occurred_at_ms, '
        "content_version, fuel_max, fuel_regen_minutes) VALUES ('x', "
        "'ad_reward_seen', '{}', 1, 1, 5, 20)",
      ),
      throwsA(anything),
    );
    expect(
      () => raw.execute(
        'INSERT INTO trip_intent (request_txn, start_txn, kind, booster) '
        "VALUES ('r', 's', 'ad_reward', 'traffic_jam')",
      ),
      throwsA(anything),
    );
  });

  test('a v5 file opens as v6, every row kept, ads null', () async {
    var e = await testEconomy(dbFile: tempDbFile());
    await e.service.grantTutorialGift(e.service.newRequestId());
    await e.service.buy(
      e.service.newRequestId(),
      kind: SkuKind.booster,
      skuId: 'change_bag',
    );
    e = await reopen(e);
    final rows = await dumpTables(e.db);
    // A booster use waiting to be charged, the only kind v5 knows.
    rows['trip_intent'] = [
      {
        'request_txn': 'r-use_booster',
        'start_txn': 's-1',
        'kind': 'use_booster',
        'booster': 'traffic_jam',
      },
    ];
    // The player state a v5 file holds (the gift granted), and the server
    // row every file has since v3.
    rows['player_state'] = [
      {
        'id': 1,
        'display_name': null,
        'tutorial_granted': 1,
        'scenes_seen': '{}',
        'requests_claimed': '[]',
      },
    ];
    rows['server_info'] = [
      {'id': 1, 'comeback_claimable': 0, 'daily': '{}'},
    ];

    final db = await olderFile(5, rows);
    addTearDown(db.close);
    await olderSchemas.migrateAndValidate(db, 6);
    final migrated = await dumpTables(db);

    expect(migrated['ledger_ops'], rows['ledger_ops']);
    expect(await _rows(db, 'trip_intent'), rows['trip_intent']);
    expect((await _rows(db, 'server_info')).single['ads'], isNull);

    final store = DriftEconomyStore(db);
    await store.checkProjection(const ProductionRules());

    await _insertOp(db, 'ad_reward_seen', 0xfff1);
    expect((await _rows(db, 'ledger_ops')).last['op_type'], 'ad_reward_seen');
    await _insertIntent(db, 'ad_reward');
    expect((await _rows(db, 'trip_intent')).map((r) => r['kind']), [
      'use_booster',
      'ad_reward',
    ]);
  });

  test('a new file takes ad_reward_seen and ad_reward', () async {
    final e = await testEconomy();
    await _insertOp(e.db, 'ad_reward_seen', 0xf100);
    await _insertIntent(e.db, 'ad_reward');
    await expectLater(_insertIntent(e.db, 'other'), throwsA(anything));
  });
}
