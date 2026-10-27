// The next `POST /v1/sync` body (specs/011-m06-identity-sync, contracts/
// sync.md "A pass", research R10, R13). Pure.
import 'dart:convert';

import 'package:wassal/core/economy/domain/op.dart';
import 'package:wassal/core/sync/domain/op_wire.dart';
import 'package:wassal/core/sync/domain/sync_batch.dart';

/// B03 takes at most 100 operations a batch.
const maxBatchOps = 100;

/// The encoded body's cap: a margin under B03's 256 KB.
const maxBatchBytes = 200 * 1024;

/// What to send next.
sealed class BatchPlan {
  const BatchPlan();
}

/// Nothing is pending.
final class NothingPending extends BatchPlan {
  const NothingPending();
}

/// The first pending operation alone is over the size cap: it is set aside
/// as rejected `payload_too_large` (R13).
final class OversizedOp extends BatchPlan {
  const OversizedOp(this.op);

  final LedgerOp op;
}

final class NextBatch extends BatchPlan {
  const NextBatch(this.batch);

  final SyncBatch batch;
}

/// The longest prefix of [pending] (in `seq` order) of at most [maxOps]
/// operations whose body stays within [maxBytes].
BatchPlan planBatch(
  List<LedgerOp> pending, {
  required int baseStateVersion,
  int maxOps = maxBatchOps,
  int maxBytes = maxBatchBytes,
}) {
  if (pending.isEmpty) return const NothingPending();
  // The envelope, then each operation and the comma before it: the same
  // compact JSON the client sends.
  var bytes = _size({
    'base_state_version': baseStateVersion,
    'ops': <Object>[],
  });
  final ops = <LedgerOp>[];
  final wires = <Map<String, Object?>>[];
  for (final op in pending.take(maxOps)) {
    final wire = opWire(op);
    final added = _size(wire) + (ops.isEmpty ? 0 : 1);
    if (bytes + added > maxBytes) break;
    bytes += added;
    ops.add(op);
    wires.add(wire);
  }
  if (ops.isEmpty) return OversizedOp(pending.first);
  final body = {'base_state_version': baseStateVersion, 'ops': wires};
  return NextBatch(
    SyncBatch(
      ops: List.unmodifiable(ops),
      baseStateVersion: baseStateVersion,
      body: body,
      encodedBytes: _size(body),
    ),
  );
}

/// The operation count after a size refusal (R13): half, at least one.
int halved(int count) => count <= 1 ? 1 : count ~/ 2;

int _size(Object? json) => utf8.encode(jsonEncode(json)).length;
