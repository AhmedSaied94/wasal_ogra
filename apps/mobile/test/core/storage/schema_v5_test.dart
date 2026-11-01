import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/economy/domain/economy_state.dart';
import 'package:wassal/core/economy/domain/rules.dart';
import 'package:wassal/core/economy/drift_economy_store.dart';
import 'package:wassal/core/storage/app_database.dart';

import '../../helpers/economy.dart';
import '../../helpers/older_schema.dart';

// Schema v5 (specs/015-m10-apartment-story/data-model.md "Drift schema 5"):
// the log's two story types, and `player_state`'s scenes seen and claimed
// requests. The generated migration test checks the shapes; these check the
// rows.

Future<List<Map<String, Object?>>> _rows(
  AppDatabase db,
  String table,
) async => [
  for (final r in await db.customSelect('SELECT * FROM $table').get()) r.data,
];

/// Inserts one log row of [type], with every other column valid.
Future<void> _insertOp(AppDatabase db, String type, int n) =>
    db.customStatement(
      'INSERT INTO ledger_ops (txn_id, op_type, payload, occurred_at_ms, '
      'content_version, fuel_max, fuel_regen_minutes) VALUES '
      "('0192f3a1-7b2c-7d4e-8f00-${n.toRadixString(16).padLeft(12, '0')}', "
      "'$type', '{}', 1, 1, 5, 20)",
    );

void main() {
  test('the log accepts all eleven wire names', () async {
    final e = await testEconomy();
    final types = [
      'trip_start',
      'trip_result',
      'ad_reward',
      'spend_jenehat',
      'spend_bonat',
      'use_booster',
      'comeback_gift',
      'settings_update',
      'tutorial_gift',
      'story_progress',
      'claim_request',
    ];
    for (final (i, type) in types.indexed) {
      await _insertOp(e.db, type, 0xf000 + i);
    }
    expect((await _rows(e.db, 'ledger_ops')).map((r) => r['op_type']), types);
  });

  test('player_state takes the two story columns empty', () async {
    final e = await testEconomy();
    await e.db.customStatement('INSERT INTO player_state (id) VALUES (1)');
    expect(await _rows(e.db, 'player_state'), [
      {
        'id': 1,
        'display_name': null,
        'tutorial_granted': 0,
        'scenes_seen': '{}',
        'requests_claimed': '[]',
      },
    ]);
    for (final column in ['scenes_seen', 'requests_claimed']) {
      await expectLater(
        e.db.customStatement('UPDATE player_state SET $column = NULL'),
        throwsA(anything),
        reason: column,
      );
    }
  });

  test('the store writes both, sorted, and reads them back', () async {
    final e = await testEconomy(
      dbFile: tempDbFile(),
      firstState: (nowMs) =>
          EconomyState.newPlayer(fuelMax: 8, nowMs: nowMs).copyWith(
            ownership: {
              (SkuKind.item, 'salon.nish'): Owned(
                kind: SkuKind.item,
                variantId: 'crystal',
                acquiredAtMs: nowMs,
              ),
            },
          ),
    );
    await e.service.recordScene(
      e.service.newRequestId(),
      chapterId: ChapterId.ch4Salon,
      sceneId: 'family_visit',
    );
    await e.service.recordScene(
      e.service.newRequestId(),
      chapterId: ChapterId.ch1FirstJob,
      sceneId: 'the_stand',
    );
    await e.service.claimRequest(
      e.service.newRequestId(),
      requestId: 'req_nish_crystal',
    );

    final rows = await _rows(e.db, 'player_state');
    expect(
      rows.single['scenes_seen'],
      '{"ch1_first_job":["the_stand"],'
      '"ch4_salon":["family_visit"]}',
    );
    expect(rows.single['requests_claimed'], '["req_nish_crystal"]');
    final reopened = await reopen(e);
    expect(reopened.service.view.scenesSeen['ch4_salon'], {'family_visit'});
    expect(reopened.service.view.requestsClaimed, {'req_nish_crystal'});
  });

  test('a v4 file opens as v5, every row kept and the story empty', () async {
    var e = await testEconomy(dbFile: tempDbFile());
    // A v4 file's log: only the types v4 knows.
    await e.service.grantTutorialGift(e.service.newRequestId());
    await e.service.buy(
      e.service.newRequestId(),
      kind: SkuKind.booster,
      skuId: 'change_bag',
    );
    e = await reopen(e);
    final rows = await dumpTables(e.db);
    // The player state a v4 file holds; the two story columns are v5's.
    rows['player_state'] = [
      {'id': 1, 'display_name': null, 'tutorial_granted': 1},
    ];

    final db = await olderFile(4, rows);
    addTearDown(db.close);
    await olderSchemas.migrateAndValidate(db, 5);
    final migrated = await dumpTables(db);

    // Every row kept, and the two story columns added as their defaults.
    expect(migrated['ledger_ops'], rows['ledger_ops']);
    expect(await _rows(db, 'player_state'), [
      {
        'id': 1,
        'display_name': null,
        'tutorial_granted': 1,
        'scenes_seen': '{}',
        'requests_claimed': '[]',
      },
    ]);

    final store = DriftEconomyStore(db);
    await store.checkProjection(const ProductionRules());
    final state = (await store.load()).state;
    expect(state.scenesSeen, isEmpty);
    expect(state.requestsClaimed, isEmpty);
    expect(state.displayName, isNull);
    expect(state.tutorialGranted, isTrue);

    // The log takes the new types after its last seq, and the fold reads one
    // back into the story state.
    await _insertOp(db, 'story_progress', 0xfff0);
    expect((await _rows(db, 'ledger_ops')).last['op_type'], 'story_progress');
  });
}
