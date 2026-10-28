// What a finished trip hands its result screen (specs/013-m08-home-result,
// data-model `ResultArgs`, research R14): the route's `extra`.
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/core/economy/domain/txn_id.dart';

final class ResultArgs {
  const ResultArgs({
    required this.result,
    required this.startTxn,
    required this.replay,
    required this.bestStarsBefore,
    required this.jenehatBefore,
  });

  /// The engine's.
  final TripResult result;

  /// Matches `lastResult.startTxn` for the ×2 state.
  final TxnId startTxn;

  /// The trip at its end, for the quote.
  final ReplayRecord replay;

  /// The trip's best stars, read just before the result was recorded.
  final int bestStarsBefore;

  /// The JENEHAT balance, read just before the result was recorded.
  final int jenehatBefore;

  @override
  bool operator ==(Object other) =>
      other is ResultArgs &&
      other.startTxn == startTxn &&
      other.bestStarsBefore == bestStarsBefore &&
      other.jenehatBefore == jenehatBefore &&
      other.result.commandLogHash == result.commandLogHash &&
      other.result.tripId == result.tripId;

  @override
  int get hashCode => Object.hash(
    startTxn,
    bestStarsBefore,
    jenehatBefore,
    result.tripId,
    result.commandLogHash,
  );

  @override
  String toString() =>
      'ResultArgs(${result.tripId} $startTxn, before: $bestStarsBefore '
      'stars, $jenehatBefore JENEHAT)';
}
