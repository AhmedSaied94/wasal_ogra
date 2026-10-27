// What the sync reports (specs/011-m06-identity-sync, contracts/sync.md
// "Events"): for M15's reports, the debug card and the rollback toast.
import 'package:wassal/core/sync/domain/pass.dart';

/// Why the full state was taken (research R12).
enum StateWhy { stale, ahead, diverged, account, firstOpen }

sealed class SyncEvent {
  const SyncEvent();
}

final class PassEnded extends SyncEvent {
  const PassEnded(this.outcome, {required this.durationMs});

  final PassOutcome outcome;
  final int durationMs;

  @override
  String toString() => 'PassEnded($outcome, ${durationMs}ms)';
}

/// The server rejected an operation.
final class OpRejected extends SyncEvent {
  const OpRejected(this.txnId, this.opType, this.reason);

  final String txnId;
  final String opType;
  final String reason;

  @override
  String toString() => 'OpRejected($opType $reason)';
}

/// The phone set an operation aside (research R13).
final class OpSetAside extends SyncEvent {
  const OpSetAside(this.txnId, this.opType, this.reason);

  final String txnId;
  final String opType;
  final String reason;

  @override
  String toString() => 'OpSetAside($opType $reason)';
}

/// Another player's state replaced this one's pending operations (R7).
final class OpsDropped extends SyncEvent {
  const OpsDropped(this.count, {this.reason = 'account_changed'});

  final int count;
  final String reason;
}

final class StateTaken extends SyncEvent {
  const StateTaken(this.stateVersion, this.why);

  final int stateVersion;
  final StateWhy why;

  @override
  String toString() => 'StateTaken($stateVersion, ${why.name})';
}

/// A pass rolled back something the player could see: the toast, once,
/// off the trip screen (research R14).
final class BalanceCorrected extends SyncEvent {
  const BalanceCorrected();
}

/// What the debug card shows (research R22).
final class SyncSnapshot {
  const SyncSnapshot({
    required this.running,
    this.lastOutcome,
    this.lastEndedAtMs,
    this.lastError,
    this.backoffUntilMs,
    this.heldUntilLaunch = false,
    this.lastDurationMs,
    this.setAsideSinceLaunch = 0,
  });

  final bool running;
  final PassOutcome? lastOutcome;

  /// On the sync's uptime clock.
  final int? lastEndedAtMs;
  final String? lastError;
  final int? backoffUntilMs;

  /// A refusal no retry fixes: the queue waits for the next launch (R13).
  final bool heldUntilLaunch;

  /// How long the last pass took.
  final int? lastDurationMs;

  /// Operations set aside locally (R13) since this launch.
  final int setAsideSinceLaunch;
}
