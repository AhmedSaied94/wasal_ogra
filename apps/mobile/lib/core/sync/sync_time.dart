// The sync's clock (specs/011-m06-identity-sync, research R9): the uptime
// counter for spacing and backoff, which no clock change moves, and its
// waits and timers. Tests use a fake that moves by hand.
import 'dart:async';

abstract interface class SyncTime {
  /// The uptime counter, in milliseconds.
  int nowMs();

  /// Completes after [duration].
  Future<void> wait(Duration duration);

  /// Runs [callback] after [duration], unless cancelled.
  Timer after(Duration duration, void Function() callback);
}

/// [SyncTime] on the trusted clock's uptime counter and real timers.
final class RealSyncTime implements SyncTime {
  const RealSyncTime(this._elapsedMs);

  final int Function() _elapsedMs;

  @override
  int nowMs() => _elapsedMs();

  @override
  Future<void> wait(Duration duration) => Future<void>.delayed(duration);

  @override
  Timer after(Duration duration, void Function() callback) =>
      Timer(duration, callback);
}
