// One `POST /v1/sync` body (specs/011-m06-identity-sync, data-model.md
// "Domain values", contracts/sync.md "Batching").
import 'package:wassal/core/economy/domain/op.dart';

final class SyncBatch {
  const SyncBatch({
    required this.ops,
    required this.baseStateVersion,
    required this.body,
    required this.encodedBytes,
  });

  /// In `seq` order.
  final List<LedgerOp> ops;

  /// The base's `state_version`, or 0 before the first.
  final int baseStateVersion;

  /// The request body, as sent.
  final Map<String, Object?> body;

  /// The UTF-8 size of the encoded [body].
  final int encodedBytes;

  @override
  String toString() =>
      'SyncBatch(${ops.length} ops, base $baseStateVersion, $encodedBytes B)';
}
