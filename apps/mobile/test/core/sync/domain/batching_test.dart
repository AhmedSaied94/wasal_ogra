import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/economy/domain/op.dart';
import 'package:wassal/core/economy/domain/txn_id.dart';
import 'package:wassal/core/sync/domain/batching.dart';

// Batches within B03's limits (specs/011-m06-identity-sync, contracts/
// sync.md "A pass", research R10, R13).

LedgerOp _op(int seq, {int resultBytes = 600}) => LedgerOp(
  seq: seq,
  op: Op(
    txnId: TxnId.parse(
      '0192f3a1-7b2c-7d4e-8f00-${seq.toRadixString(16).padLeft(12, '0')}',
    ),
    type: OpType.tripResult,
    payload: {'result': 'x' * resultBytes},
    occurredAtMs: 1792627200000 + seq,
    contentVersion: 1,
    fuelMax: 5,
    fuelRegenMinutes: 20,
  ),
  syncStatus: SyncStatus.pending,
);

List<LedgerOp> _ops(int count, {int resultBytes = 600}) => [
  for (var i = 1; i <= count; i++) _op(i, resultBytes: resultBytes),
];

NextBatch _next(BatchPlan plan) => plan as NextBatch;

void main() {
  test('nothing pending is NothingPending', () {
    expect(planBatch(const [], baseStateVersion: 0), isA<NothingPending>());
  });

  test('at most 100 operations', () {
    final batch = _next(planBatch(_ops(250), baseStateVersion: 3)).batch;
    expect(batch.ops, hasLength(100));
    expect(batch.ops.first.seq, 1);
    expect(batch.ops.last.seq, 100);
  });

  test('the body stays within 200 KiB; with 8 KB results fewer fit', () {
    final batch = _next(
      planBatch(_ops(100, resultBytes: 8000), baseStateVersion: 3),
    ).batch;
    expect(batch.ops.length, lessThan(100));
    expect(batch.ops.length, greaterThan(20));
    final encoded = utf8.encode(jsonEncode(batch.body)).length;
    expect(batch.encodedBytes, encoded);
    expect(encoded, lessThanOrEqualTo(maxBatchBytes));
    // One more would not have fit.
    final bigger = _next(
      planBatch(
        _ops(batch.ops.length + 1, resultBytes: 8000),
        baseStateVersion: 3,
        maxOps: batch.ops.length + 1,
        maxBytes: encoded,
      ),
    ).batch;
    expect(bigger.ops, hasLength(batch.ops.length));
  });

  test('the body is base_state_version and the ops in seq order', () {
    final batch = _next(planBatch(_ops(3), baseStateVersion: 41)).batch;
    expect(batch.baseStateVersion, 41);
    expect(batch.body['base_state_version'], 41);
    final ops = batch.body['ops']! as List<Object?>;
    expect(
      [for (final o in ops) (o! as Map)['client_txn_id']],
      [for (final op in batch.ops) op.op.txnId.value],
    );
  });

  test('base_state_version 0 before any', () {
    expect(_next(planBatch(_ops(1), baseStateVersion: 0)).batch.body, {
      'base_state_version': 0,
      'ops': isA<List<Object?>>(),
    });
  });

  test('halving after a size refusal', () {
    expect(halved(100), 50);
    expect(halved(3), 1);
    expect(halved(1), 1);
    final batch = _next(
      planBatch(_ops(100), baseStateVersion: 0, maxOps: halved(100)),
    ).batch;
    expect(batch.ops, hasLength(50));
  });

  test('a single operation over the cap is reported for setting aside', () {
    final pending = [_op(1, resultBytes: maxBatchBytes), _op(2)];
    final plan = planBatch(pending, baseStateVersion: 0);
    expect(plan, isA<OversizedOp>());
    expect((plan as OversizedOp).op.seq, 1);
  });
}
