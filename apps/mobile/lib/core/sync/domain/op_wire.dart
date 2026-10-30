// A stored operation as `POST /v1/sync` sends it (specs/011-m06-identity-
// sync, contracts/sync.md "The wire", research R10). Pure: the local
// columns (deltas, fuel tunables, the trip's bound, the reason) never
// leave the phone.
import 'package:wassal/core/economy/domain/op.dart';
import 'package:wassal/core/sync/domain/wire/iso_time.dart';

/// The types whose payload carries `content_version`, added from the row's
/// column (B03 operations.md).
const contentVersionTypes = {
  OpType.tripStart,
  OpType.spendJenehat,
  OpType.spendBonat,
  // M10's two: the server checks the scene and the request against the pack
  // (specs/015-m10-apartment-story, contracts/economy-ops.md "Wire").
  OpType.storyProgress,
  OpType.claimRequest,
};

/// [op] on the wire: `{client_txn_id, op_type, occurred_at, payload}`.
Map<String, Object?> opWire(LedgerOp op) {
  final Op(:txnId, :type, :payload, :occurredAtMs, :contentVersion) = op.op;
  return {
    'client_txn_id': txnId.value,
    'op_type': type.wire,
    'occurred_at': msToIso(occurredAtMs),
    'payload': {
      ...payload,
      if (contentVersionTypes.contains(type)) 'content_version': contentVersion,
    },
  };
}
