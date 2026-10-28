// The only code that writes the first session's flags
// (specs/012-m07-onboarding/data-model.md "first_session", research R2).
// One row, made by the first write. Every write is idempotent, and the step
// never goes down; `economy_writes_test.dart` keeps every other file out.
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:wassal/core/storage/app_database.dart';
import 'package:wassal/features/onboarding/domain/first_session.dart';

final class DriftFirstSessionStore {
  DriftFirstSessionStore(this._db);

  final AppDatabase _db;

  /// The flags now, then after every write.
  Stream<FirstSessionFlags> watch() =>
      _db.select(_db.firstSessionTable).watchSingleOrNull().map(_flagsOf);

  Future<FirstSessionFlags> read() async =>
      _flagsOf(await _db.select(_db.firstSessionTable).getSingleOrNull());

  /// The opening scene finished or was skipped; the first time stays.
  Future<void> markOpeningDone(int nowMs) => _update(
    (row) => row.openingDoneAtMs == null
        ? FirstSessionTableCompanion(openingDoneAtMs: Value(nowMs))
        : null,
  );

  /// [sceneId] became due by a first finish; added once.
  Future<void> addSceneDue(String sceneId) => _update((row) {
    final due = _ids(row.scenesDue);
    if (due.contains(sceneId)) return null;
    return FirstSessionTableCompanion(
      scenesDue: Value(jsonEncode([...due, sceneId])),
    );
  });

  /// [sceneId] finished or was skipped; added once.
  Future<void> markSceneSeen(String sceneId) => _update((row) {
    final seen = _ids(row.scenesSeen);
    if (seen.contains(sceneId)) return null;
    return FirstSessionTableCompanion(
      scenesSeen: Value(jsonEncode([...seen, sceneId])),
    );
  });

  /// The fuel lesson's button was pressed; the first time stays.
  Future<void> markFuelLessonDone(int nowMs) => _update(
    (row) => row.fuelLessonDoneAtMs == null
        ? FirstSessionTableCompanion(fuelLessonDoneAtMs: Value(nowMs))
        : null,
  );

  /// Raises the step to [step]. Returns whether it rose: a lower or equal
  /// step changes nothing. Throws [ArgumentError] outside 0 to 8.
  Future<bool> reachStep(int step) async {
    RangeError.checkValueInInterval(step, 0, lastFirstSessionStep, 'step');
    var rose = false;
    await _update((row) {
      if (step <= row.stepReached) return null;
      rose = true;
      return FirstSessionTableCompanion(stepReached: Value(step));
    });
    return rose;
  }

  /// The tutorial is done; the first time stays.
  Future<void> markDone(int nowMs) => _update(
    (row) => row.doneAtMs == null
        ? FirstSessionTableCompanion(doneAtMs: Value(nowMs))
        : null,
  );

  /// Reads the row (an absent one as its defaults), and writes what
  /// [change] gives, if anything, in one transaction.
  Future<void> _update(
    FirstSessionTableCompanion? Function(FirstSessionRow row) change,
  ) => _db.transaction(() async {
    final row =
        await _db.select(_db.firstSessionTable).getSingleOrNull() ??
        const FirstSessionRow(
          id: 1,
          scenesDue: '[]',
          scenesSeen: '[]',
          stepReached: 0,
        );
    final update = change(row);
    if (update == null) return;
    await _db
        .into(_db.firstSessionTable)
        .insertOnConflictUpdate(
          row
              .toCompanion(true)
              .copyWith(
                openingDoneAtMs: update.openingDoneAtMs.present
                    ? update.openingDoneAtMs
                    : null,
                scenesDue: update.scenesDue.present ? update.scenesDue : null,
                scenesSeen: update.scenesSeen.present
                    ? update.scenesSeen
                    : null,
                fuelLessonDoneAtMs: update.fuelLessonDoneAtMs.present
                    ? update.fuelLessonDoneAtMs
                    : null,
                stepReached: update.stepReached.present
                    ? update.stepReached
                    : null,
                doneAtMs: update.doneAtMs.present ? update.doneAtMs : null,
              ),
        );
  });
}

FirstSessionFlags _flagsOf(FirstSessionRow? row) => row == null
    ? FirstSessionFlags.empty
    : FirstSessionFlags(
        openingDoneAtMs: row.openingDoneAtMs,
        scenesDue: _ids(row.scenesDue),
        scenesSeen: _ids(row.scenesSeen),
        fuelLessonDoneAtMs: row.fuelLessonDoneAtMs,
        stepReached: row.stepReached,
        doneAtMs: row.doneAtMs,
      );

/// A stored JSON array of ids. Anything else reads as none: the store
/// writes only arrays of strings.
List<String> _ids(String json) => switch (jsonDecode(json)) {
  final List<Object?> ids => List.unmodifiable(ids.whereType<String>()),
  _ => const [],
};
