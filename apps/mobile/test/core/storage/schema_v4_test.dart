import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/economy/domain/rules.dart';
import 'package:wassal/core/economy/drift_economy_store.dart';
import 'package:wassal/core/storage/app_database.dart';

import '../../helpers/economy.dart';
import '../../helpers/older_schema.dart';

// Schema v4 (specs/012-m07-onboarding/data-model.md "App database v4"): the
// log's two new types, the driver's name and the tutorial grant in
// `player_state`, and the first session's flags in `first_session`. The
// generated migration test checks the shapes; these check the rows.

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

/// Inserts one log row of [type], with every other column valid.
Future<void> _insertOp(AppDatabase db, String type, int n) =>
    db.customStatement(
      'INSERT INTO ledger_ops (txn_id, op_type, payload, occurred_at_ms, '
      'content_version, fuel_max, fuel_regen_minutes) VALUES '
      "('0192f3a1-7b2c-7d4e-8f00-${n.toRadixString(16).padLeft(12, '0')}', "
      "'$type', '{}', 1, 1, 5, 20)",
    );

void main() {
  test('the log accepts all nine wire names', () async {
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
    ];
    for (final (i, type) in types.indexed) {
      await _insertOp(e.db, type, 0xf000 + i);
    }
    expect((await _rows(e.db, 'ledger_ops')).map((r) => r['op_type']), types);
  });

  test('the log refuses an op type v4 doesn\'t list', () async {
    final e = await testEconomy();
    await expectLater(
      _insertOp(e.db, 'story_progress', 0xfffe),
      throwsA(anything),
    );
  });

  test('a new file has no player_state or first_session row', () async {
    final e = await testEconomy();
    expect(await _rows(e.db, 'player_state'), isEmpty);
    expect(await _rows(e.db, 'first_session'), isEmpty);
  });

  test('an absent player_state reads as no name and no grant', () async {
    final e = await testEconomy();
    final state = (await e.store.load()).state;
    expect(state.displayName, isNull);
    expect(state.tutorialGranted, isFalse);
  });

  test('player_state and first_session each allow only id 1', () async {
    final e = await testEconomy();
    await e.db.customStatement(
      "INSERT INTO player_state (id, display_name, tutorial_granted) "
      "VALUES (1, 'x', 0)",
    );
    await expectLater(
      e.db.customStatement(
        'INSERT INTO player_state (id, tutorial_granted) VALUES (2, 0)',
      ),
      throwsA(anything),
    );
    await e.db.customStatement('INSERT INTO first_session (id) VALUES (1)');
    await expectLater(
      e.db.customStatement('INSERT INTO first_session (id) VALUES (2)'),
      throwsA(anything),
    );
  });

  test(
    'first_session takes its defaults, and step_reached is 0\u20138',
    () async {
      final e = await testEconomy();
      await e.db.customStatement('INSERT INTO first_session (id) VALUES (1)');
      expect(await _rows(e.db, 'first_session'), [
        {
          'id': 1,
          'opening_done_at_ms': null,
          'scenes_due': '[]',
          'scenes_seen': '[]',
          'fuel_lesson_done_at_ms': null,
          'step_reached': 0,
          'done_at_ms': null,
        },
      ]);
      await e.db.customStatement('UPDATE first_session SET step_reached = 8');
      for (final bad in [-1, 9]) {
        await expectLater(
          e.db.customStatement('UPDATE first_session SET step_reached = $bad'),
          throwsA(anything),
          reason: '$bad',
        );
      }
    },
  );

  test('player_state.tutorial_granted is not null, default false', () async {
    final e = await testEconomy();
    await e.db.customStatement('INSERT INTO player_state (id) VALUES (1)');
    expect(await _rows(e.db, 'player_state'), [
      {'id': 1, 'display_name': null, 'tutorial_granted': 0},
    ]);
    await expectLater(
      e.db.customStatement('UPDATE player_state SET tutorial_granted = NULL'),
      throwsA(anything),
    );
  });

  test('the new tables are INTEGER or TEXT: no REAL column', () async {
    final e = await testEconomy();
    for (final table in ['player_state', 'first_session']) {
      expect(
        (await _columns(e.db, table)).values.toSet(),
        everyElement(isIn(['INTEGER', 'TEXT'])),
        reason: table,
      );
    }
  });

  test('a v3 file with an economy opens as v4, every row kept', () async {
    var e = await testEconomy(dbFile: tempDbFile());
    await seedOps(e.db, e.store, count: 6);
    e = await reopen(e);
    final rows = await dumpTables(e.db);

    final db = await olderFile(3, rows);
    addTearDown(db.close);
    await olderSchemas.migrateAndValidate(db, 4);
    expect(await dumpTables(db), rows);
    expect(await _rows(db, 'player_state'), isEmpty);
    expect(await _rows(db, 'first_session'), isEmpty);

    // The economy reads it with no name and no grant, and the log takes the
    // new types after its last seq.
    final store = DriftEconomyStore(db);
    await store.checkProjection(const ProductionRules());
    final state = (await store.load()).state;
    expect(state.displayName, isNull);
    expect(state.tutorialGranted, isFalse);
    await _insertOp(db, 'tutorial_gift', 0xfff0);
    expect((await _rows(db, 'ledger_ops')).last['op_type'], 'tutorial_gift');
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
