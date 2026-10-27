import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/economy/economy.dart';
import 'package:wassal/core/economy/economy_sync.dart';
import 'package:wassal/core/sync/domain/wire/server_wallet.dart';

import '../../../helpers/economy.dart';

// An answer applies in one step (specs/011-m06-identity-sync, research
// R11): a 100-operation batch on a 50,000-row log stays under 100 ms, the
// median of five, with the rest of the log already answered.

const _ops = 50000;
const _batch = 100;
const _runs = 5;
const _budgetMs = 100;
const _player = '0192f1c3-7d1e-7a4b-9c11-000000000001';

/// Every operation of [batch] accepted, with the phone's own wallet.
Future<void> _accept(TestEconomy e, List<LedgerOp> batch, int version) async {
  final view = e.service.view;
  await e.service.applyAnswer(
    SyncAnswer(
      stateVersion: version,
      stateStale: false,
      results: [for (final op in batch) OpResult.accepted(op.op.txnId.value)],
      wallet: ServerWallet(
        jenehat: view.jenehat,
        bonat: view.bonat,
        fuel: e.service.state.fuel.liters,
        fuelMax: 5,
        fuelUpdatedAtMs: e.service.state.fuel.countedFromMs,
      ),
    ),
    batch: batch,
    playerId: _player,
  );
}

void main() {
  test(
    'a $_batch-operation answer on a $_ops-row log: ≤ $_budgetMs ms',
    () async {
      final seeding = await testEconomy(dbFile: tempDbFile());
      await seedOps(seeding.db, seeding.store, count: _ops);
      final e = await reopen(seeding);

      // Everything but the timed batches is answered already.
      const answered = _ops - _batch * _runs;
      await _accept(e, await e.service.pendingOps(limit: answered), 1);

      final times = <int>[];
      for (var run = 0; run < _runs; run++) {
        final batch = await e.service.pendingOps();
        expect(batch, hasLength(_batch));
        final watch = Stopwatch()..start();
        await _accept(e, batch, run + 2);
        watch.stop();
        times.add(watch.elapsedMilliseconds);
      }

      expect(e.service.pendingCount, 0);
      times.sort();
      final median = times[_runs ~/ 2];
      stdout.writeln('applyAnswer, $_batch ops on $_ops rows: $times ms');
      expect(median, lessThanOrEqualTo(_budgetMs), reason: 'runs: $times ms');
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
