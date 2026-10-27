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

/// What a sync answer's wallet decides (M06 research R11): the balances and
/// the tank, as the server counted them.
typedef ServerBalances = ({int jenehat, int bonat, FuelState fuel});

/// The base after an answer (M06 research R11): [base] folded with
/// [answered], every answered operation up to the batch's last that wasn't
/// rejected, then the server's balances and tank in place of the fold's.
/// Ownership, inventory, progress and the trip session stay the fold's.
FoldResult rebase(
  EconomyState base,
  Iterable<Op> answered,
  ServerBalances balances,
  Rules rules,
) => withServerBalances(fold(base, answered, rules), balances);

/// [folded] with [balances] in place of its own.
FoldResult withServerBalances(FoldResult folded, ServerBalances balances) =>
    FoldResult(
      folded.state.copyWith(
        jenehat: balances.jenehat,
        bonat: balances.bonat,
        fuel: balances.fuel,
      ),
      folded.leftOut,
    );
