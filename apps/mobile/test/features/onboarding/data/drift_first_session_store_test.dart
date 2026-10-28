import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/storage/app_database.dart';
import 'package:wassal/features/onboarding/data/drift_first_session_store.dart';
import 'package:wassal/features/onboarding/domain/first_session.dart';

// The first session's flags on a real database (specs/012-m07-onboarding/
// data-model.md "first_session"): one row, made by the first write; each
// write idempotent; the step never lowered.

Future<(AppDatabase, DriftFirstSessionStore)> _open() async {
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  return (db, DriftFirstSessionStore(db));
}

Future<int> _rowCount(AppDatabase db) async =>
    (await db.customSelect('SELECT * FROM first_session').get()).length;

void main() {
  test('no row reads as the empty flags', () async {
    final (db, store) = await _open();
    expect(await store.read(), FirstSessionFlags.empty);
    expect(await _rowCount(db), 0);
  });

  test('the first write makes the row, and only one', () async {
    final (db, store) = await _open();
    await store.markOpeningDone(100);
    await store.reachStep(1);
    expect(await _rowCount(db), 1);
    expect(
      await store.read(),
      const FirstSessionFlags(openingDoneAtMs: 100, stepReached: 1),
    );
  });

  test(
    'the opening, the fuel lesson and the end keep their first time',
    () async {
      final (_, store) = await _open();
      await store.markOpeningDone(100);
      await store.markOpeningDone(200);
      await store.markFuelLessonDone(300);
      await store.markFuelLessonDone(400);
      await store.markDone(500);
      await store.markDone(600);
      final flags = await store.read();
      expect(flags.openingDoneAtMs, 100);
      expect(flags.fuelLessonDoneAtMs, 300);
      expect(flags.doneAtMs, 500);
    },
  );

  test('scenes are added once each, in order', () async {
    final (_, store) = await _open();
    await store.addSceneDue('the_stand');
    await store.addSceneDue('salma_again');
    await store.addSceneDue('the_stand');
    await store.markSceneSeen('the_stand');
    await store.markSceneSeen('the_stand');
    final flags = await store.read();
    expect(flags.scenesDue, ['the_stand', 'salma_again']);
    expect(flags.scenesSeen, ['the_stand']);
  });

  test('the step never goes down', () async {
    final (_, store) = await _open();
    expect(await store.reachStep(4), isTrue);
    expect(await store.reachStep(2), isFalse);
    expect(await store.reachStep(4), isFalse);
    expect((await store.read()).stepReached, 4);
    expect(await store.reachStep(8), isTrue);
    expect((await store.read()).stepReached, 8);
  });

  test('a step outside 0–8 is an error', () async {
    final (_, store) = await _open();
    expect(() => store.reachStep(9), throwsArgumentError);
    expect(() => store.reachStep(-1), throwsArgumentError);
  });

  test('the stream gives the row after each write', () async {
    final (_, store) = await _open();
    final seen = <FirstSessionFlags>[];
    final subscription = store.watch().listen(seen.add);
    addTearDown(subscription.cancel);
    await pumpEventQueue();
    await store.markOpeningDone(100);
    await pumpEventQueue();
    await store.addSceneDue('the_stand');
    await pumpEventQueue();
    expect(seen.first, FirstSessionFlags.empty);
    expect(seen.last.scenesDue, ['the_stand']);
    expect(seen.last.openingDoneAtMs, 100);
  });
}
