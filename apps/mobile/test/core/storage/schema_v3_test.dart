import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/economy/domain/economy_state.dart';
import 'package:wassal/core/economy/domain/rules.dart';
import 'package:wassal/core/economy/drift_economy_store.dart';
import 'package:wassal/core/economy/economy.dart' show OpApplied;
import 'package:wassal/core/storage/app_database.dart';

import '../../helpers/economy.dart';
import '../../helpers/older_schema.dart';

// Schema v3 (specs/011-m06-identity-sync, data-model.md "Tables (schema
// v3)"): the account and the last bootstrap, one row each; the base's
// player; ownership rows without the operation that bought them; and
// `comeback_gift` in the log. The generated migration test checks the
// shapes; these check the rows.

Future<List<Map<String, Object?>>> _rows(
  AppDatabase db,
  String table,
) async => [
  for (final r in await db.customSelect('SELECT * FROM $table').get()) r.data,
];

Future<Map<String, String>> _columns(AppDatabase db, String table) async => {
  for (final r in await db.customSelect('PRAGMA table_info($table)').get())
    r.data['name']! as String: r.data['type']! as String,
};

Future<Map<String, bool>> _notNull(AppDatabase db, String table) async => {
  for (final r in await db.customSelect('PRAGMA table_info($table)').get())
    r.data['name']! as String: r.data['notnull'] == 1,
};

EconomyState _rich(int nowMs) => EconomyState.newPlayer(
  fuelMax: 5,
  nowMs: nowMs,
).copyWith(jenehat: 5000, bonat: 40);

void main() {
  test('a new database has one account row and one empty server row', () async {
    final e = await testEconomy();
    expect(await _rows(e.db, 'account'), [
      {
        'id': 1,
        'status': 'none',
        'player_id': null,
        'providers': '[]',
        'display_name': null,
        'driver_level': null,
        'first_open_at_ms': null,
        'restored_at_ms': null,
        'updated_at_ms': testEpochMs,
      },
    ]);
    expect(await _rows(e.db, 'server_info'), [
      {
        'id': 1,
        'received_at_ms': null,
        'server_time_ms': null,
        'state_version': null,
        'content_version': null,
        'client': null,
        'entitlements': null,
        'daily': null,
        'comeback_claimable': 0,
        'comeback_claimed_at_ms': null,
        'comeback_answered_at_ms': null,
      },
    ]);
  });

  test('the new and changed columns are INTEGER or TEXT, as v3 says', () async {
    final e = await testEconomy();
    for (final table in ['account', 'server_info']) {
      expect(
        (await _columns(e.db, table)).values.toSet(),
        everyElement(isIn(['INTEGER', 'TEXT'])),
        reason: table,
      );
    }
    expect((await _columns(e.db, 'projection_base'))['player_id'], 'TEXT');
    expect((await _notNull(e.db, 'projection_base'))['player_id'], isFalse);
    expect((await _notNull(e.db, 'ownership'))['acquired_by'], isFalse);
  });

  test(
    'ownership keeps a row with no acquired_by, and reads it back',
    () async {
      final e = await testEconomy(
        firstState: (nowMs) => _rich(nowMs).copyWith(
          ownership: {
            (SkuKind.vehicle, 'micro_old'): Owned(
              kind: SkuKind.vehicle,
              acquiredAtMs: nowMs,
            ),
          },
        ),
      );
      final owned = (await e.store.load()).state.ownership.values.single;
      expect(owned.acquiredBy, isNull);
      expect((await _rows(e.db, 'ownership')).single['acquired_by'], isNull);
    },
  );

  test('a v2 file with an economy opens through v3, every row kept', () async {
    // An economy with trips and a purchase, written by the current code.
    var e = await testEconomy(dbFile: tempDbFile(), firstState: _rich);
    await seedOps(e.db, e.store, count: 30, bonat: 40);
    e = await reopen(e);
    final bought = await e.service.buy(
      e.service.newRequestId(),
      kind: SkuKind.item,
      skuId: 'salon.nish',
      variantId: 'classic',
    );
    expect(bought, isA<OpApplied>());
    final rows = await dumpTables(e.db);

    // The same rows in a file v2 made.
    final db = await olderFile(2, rows);
    addTearDown(db.close);
    // Through v3 to the current version: the economy reads every table of it.
    await olderSchemas.migrateAndValidate(db, db.schemaVersion);
    expect(await dumpTables(db), rows);
    final account = (await _rows(db, 'account')).single;
    expect(account['status'], 'none');
    expect(account['providers'], '[]');
    expect(
      account['updated_at_ms'],
      rows['clock_anchor']!.single['latest_trusted_ms'],
    );
    expect((await _rows(db, 'server_info')).single['comeback_claimable'], 0);

    // The economy reads it, and the log goes on after its last seq.
    final store = DriftEconomyStore(db);
    await store.checkProjection(const ProductionRules());
    final last = rows['ledger_ops']!.last['seq']! as int;
    await db.customStatement(
      'INSERT INTO ledger_ops (txn_id, op_type, payload, occurred_at_ms, '
      'content_version, fuel_max, fuel_regen_minutes) VALUES '
      "('0192f3a1-7b2c-7d4e-8f00-00000000ffff', 'comeback_gift', '{}', 1, 1, "
      '5, 20)',
    );
    expect(
      (await db
              .customSelect('SELECT MAX(seq) AS s FROM ledger_ops')
              .getSingle())
          .data['s'],
      last + 1,
    );
    // The rebuilt log keeps its two indexes.
    final indexes = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'index' "
          "AND tbl_name = 'ledger_ops' AND sql IS NOT NULL",
        )
        .get();
    expect(
      {for (final i in indexes) i.data['name']},
      {'ledger_ops_sync', 'ledger_ops_ref'},
    );
  });
}
