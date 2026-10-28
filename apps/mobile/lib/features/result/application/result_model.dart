// What the result screen shows (specs/013-m08-home-result,
// contracts/result.md): the trip's own result when it handed one over;
// else the last result's pay, if it was a finished trip's; else nothing,
// and the screen goes Home.
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/core/content/content_providers.dart';
import 'package:wassal/core/economy/economy_providers.dart';
import 'package:wassal/core/progress/application/player_progress_provider.dart';
import 'package:wassal/features/home/domain/savings_target.dart';
import 'package:wassal/features/result/domain/result_args.dart';
import 'package:wassal/features/result/domain/summary.dart';

part 'result_model.g.dart';

/// The apartment card (FR-043): the target as Home's savings card has it
/// after the pay.
final class ApartmentProgress {
  const ApartmentProgress({required this.target, required this.fromJenehat});

  final SavingsTarget target;

  /// The balance before this trip's pay, where the bar's gain starts; null
  /// without the trip's hand-over.
  final int? fromJenehat;

  @override
  bool operator ==(Object other) =>
      other is ApartmentProgress &&
      other.target == target &&
      other.fromJenehat == fromJenehat;

  @override
  int get hashCode => Object.hash(target, fromJenehat);
}

sealed class ResultModel {
  const ResultModel();
}

/// A finished trip's result, as the trip handed it over.
final class FullResult extends ResultModel {
  const FullResult({
    required this.summary,
    required this.args,
    required this.apartment,
  });

  final ResultSummary summary;
  final ResultArgs args;
  final ApartmentProgress apartment;
}

/// Opened without the hand-over (a link, or the app restarted here): the
/// last result's pay only (FR-036).
final class PayOnlyResult extends ResultModel {
  const PayOnlyResult({
    required this.heading,
    required this.payJenehat,
    required this.apartment,
  });

  /// Null when the pack lacks the route's trip.
  final ResultHeading? heading;
  final int payJenehat;
  final ApartmentProgress apartment;
}

/// Nothing to show: Home.
final class NoResult extends ResultModel {
  const NoResult();
}

@riverpod
ResultModel resultModel(Ref ref, String tripId, ResultArgs? args) {
  final content = ref.watch(contentSourceProvider);
  final view = ref.watch(economyViewProvider);
  final target = savingsTarget(
    content,
    ref.watch(playerProgressProvider),
    view.jenehat,
  );
  if (args != null) {
    final summary = resultSummary(content, args, lastResult: view.lastResult);
    if (summary != null) {
      return FullResult(
        summary: summary,
        args: args,
        apartment: ApartmentProgress(
          target: target,
          fromJenehat: args.jenehatBefore,
        ),
      );
    }
  }
  final last = view.lastResult;
  if (last == null || last.outcome != TripOutcome.finished) {
    return const NoResult();
  }
  final trip = content.trip(tripId);
  return PayOnlyResult(
    heading: trip == null ? null : resultHeading(content, trip),
    payJenehat: payOf(
      last.earningsJenehat,
      lastResult: last,
      startTxn: last.startTxn,
    ),
    apartment: ApartmentProgress(target: target, fromJenehat: null),
  );
}
