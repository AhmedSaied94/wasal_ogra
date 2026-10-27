// What starts a sync pass and what it comes to (contracts/sync.md
// "`SyncEngine`").

/// What asked for a pass (research R9).
enum SyncTrigger {
  startup,
  accountActive,
  resume,
  online,

  /// A new pending operation, debounced 2 s.
  opsRecorded,
  leftTrip,

  /// Internal builds' «sync now».
  manual,

  /// The backoff's wait ended.
  retry,
}

/// Why a pass didn't run, or stopped before its next request.
enum HoldReason { trip, maintenance, account, deleted, background, refused }

sealed class PassOutcome {
  const PassOutcome();
}

/// Nothing was pending.
final class PassIdle extends PassOutcome {
  const PassIdle();

  @override
  String toString() => 'idle';
}

final class PassDone extends PassOutcome {
  const PassDone({
    required this.batches,
    required this.accepted,
    required this.rejected,
    required this.setAside,
  });

  final int batches;
  final int accepted;
  final int rejected;
  final int setAside;

  @override
  String toString() =>
      'done($batches batches, $accepted accepted, $rejected rejected, '
      '$setAside set aside)';
}

final class PassHeld extends PassOutcome {
  const PassHeld(this.reason);

  final HoldReason reason;

  @override
  String toString() => 'held(${reason.name})';
}

/// The pass backed off: the server or the network failed. [retryAtMs] is on
/// the sync's uptime clock.
final class PassFailed extends PassOutcome {
  const PassFailed(this.code, {required this.retryAtMs});

  final String code;
  final int retryAtMs;

  @override
  String toString() => 'failed($code)';
}
