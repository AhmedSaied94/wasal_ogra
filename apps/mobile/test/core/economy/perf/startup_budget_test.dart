import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/economy/domain/economy_state.dart';
import 'package:wassal/core/economy/domain/trusted_time.dart';
import 'package:wassal/core/economy/drift_economy_store.dart';
import 'package:wassal/core/storage/app_database.dart';
import 'package:wassal/core/storage/connection.dart';

import '../../../helpers/economy.dart';

// Startup reads the materialized tables, never the log (SC-005, research
// R18): with 50,000 ops stored, opening the file and loading the economy
// stays within budget, and reads no ledger_ops row. The debug fold check
// is off, as in a release build.

const _ops = 50000;
const _budgetMs = 150;

/// Counts the reads that touch the log.
final class _LedgerReads extends QueryInterceptor {
  int count = 0;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (statement.contains('ledger_ops')) count++;
    return super.runSelect(executor, statement, args);
  }
}

void main() {
  test('open + load with $_ops ops: ≤ $_budgetMs ms, no log read', () async {
    final file = tempDbFile();
    final seeding = AppDatabase(
      NativeDatabase(file, setup: configureConnection),
      firstOpen: () => FirstOpen(
        state: EconomyState.newPlayer(fuelMax: 5, nowMs: testEpochMs),
        anchor: firstAnchor(null, testEpochMs),
      ),
    );
    final last = await seedOps(
      seeding,
      DriftEconomyStore(seeding),
      count: _ops,
    );
    await seeding.close();

    final times = <int>[];
    for (var run = 0; run < 6; run++) {
      final reads = _LedgerReads();
      final watch = Stopwatch()..start();
      // The production connection: its own isolate, the same pragmas.
      final db = AppDatabase(openDatabaseFile(file).interceptWith(reads));
      await db.customSelect('SELECT 1').get();
      final opened = reads.count;
      final loaded = await DriftEconomyStore(db).load();
      watch.stop();
      await db.close();

      expect(loaded.lastSeq, _ops);
      expect(loaded.state, last);
      expect(opened, 0, reason: 'opening reads no ledger_ops row');
      expect(reads.count, 0, reason: 'load() reads no ledger_ops row');
      // The first run warms the file cache and the isolate.
      if (run > 0) times.add(watch.elapsedMilliseconds);
    }
    times.sort();
    final median = times[times.length ~/ 2];
    expect(median, lessThanOrEqualTo(_budgetMs), reason: 'runs: $times ms');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
