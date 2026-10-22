// The projection rebuilt from a base (research R5, R6).
import 'package:wassal/core/economy/domain/economy_state.dart';
import 'package:wassal/core/economy/domain/op.dart';
import 'package:wassal/core/economy/domain/rules.dart';
import 'package:wassal/core/economy/domain/txn_id.dart';

final class FoldResult {
  const FoldResult(this.state, this.leftOut);

  final EconomyState state;

  /// The operations that no longer applied, in order. Their rows stay, and
  /// so does their `pending` status (FR-046).
  final List<TxnId> leftOut;
}

/// [base] with [ops] applied in order, each one only if it still applies.
FoldResult fold(EconomyState base, Iterable<Op> ops, Rules rules) {
  var state = base;
  final leftOut = <TxnId>[];
  for (final op in ops) {
    if (rules.stillValid(state, op)) {
      state = rules.apply(state, op);
    } else {
      leftOut.add(op.txnId);
    }
  }
  return FoldResult(state, List.unmodifiable(leftOut));
}
