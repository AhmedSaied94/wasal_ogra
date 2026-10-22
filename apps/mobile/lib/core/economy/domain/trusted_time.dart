// The trusted-time arithmetic (research R9, contracts/fuel-and-time.md
// "Trusted time"): an anchor advanced by the phone's uptime counter
// (constitution VI). Every time is UTC milliseconds.
/// One reading of the phone's uptime counter.
final class BootSnapshot {
  const BootSnapshot({required this.elapsedRealtimeMs, this.bootCount});

  /// Milliseconds since boot, deep sleep included. No clock change moves it.
  final int elapsedRealtimeMs;

  /// The phone's boot count, or null when the device doesn't provide it.
  final int? bootCount;

  @override
  bool operator ==(Object other) =>
      other is BootSnapshot &&
      other.elapsedRealtimeMs == elapsedRealtimeMs &&
      other.bootCount == bootCount;

  @override
  int get hashCode => Object.hash(elapsedRealtimeMs, bootCount);

  @override
  String toString() => 'BootSnapshot($elapsedRealtimeMs, boot $bootCount)';
}

/// Where an anchor's time came from.
enum AnchorSource {
  device('device'),
  server('server');

  const AnchorSource(this.wire);

  final String wire;
}

/// The point trusted time counts from (data-model.md "ClockAnchor").
final class ClockAnchor {
  const ClockAnchor({
    required this.anchorMs,
    required this.anchorElapsedMs,
    required this.source,
    required this.latestTrustedMs,
    this.bootCount,
  });

  final int anchorMs;

  /// The uptime counter when [anchorMs] was taken.
  final int anchorElapsedMs;
  final int? bootCount;
  final AnchorSource source;

  /// The latest trusted time recorded. It never decreases.
  final int latestTrustedMs;

  ClockAnchor withLatest(int ms) => ClockAnchor(
    anchorMs: anchorMs,
    anchorElapsedMs: anchorElapsedMs,
    bootCount: bootCount,
    source: source,
    latestTrustedMs: _max(latestTrustedMs, ms),
  );

  @override
  bool operator ==(Object other) =>
      other is ClockAnchor &&
      other.anchorMs == anchorMs &&
      other.anchorElapsedMs == anchorElapsedMs &&
      other.bootCount == bootCount &&
      other.source == source &&
      other.latestTrustedMs == latestTrustedMs;

  @override
  int get hashCode => Object.hash(
    anchorMs,
    anchorElapsedMs,
    bootCount,
    source,
    latestTrustedMs,
  );

  @override
  String toString() =>
      'ClockAnchor($anchorMs @ $anchorElapsedMs, boot $bootCount, '
      '${source.wire}, latest $latestTrustedMs)';
}

/// The anchor of a new install: the device clock at the first startup. With
/// no uptime channel there is nothing to count from, so elapsed is 0.
ClockAnchor firstAnchor(BootSnapshot? snapshot, int deviceNowMs) => ClockAnchor(
  anchorMs: deviceNowMs,
  anchorElapsedMs: snapshot?.elapsedRealtimeMs ?? 0,
  bootCount: snapshot?.bootCount,
  source: AnchorSource.device,
  latestTrustedMs: deviceNowMs,
);

/// Whether the phone restarted since [anchor] was taken: its boot count
/// changed, or, when either count is missing, its uptime counter went back.
/// Without boot counts a restart with a longer uptime looks like the same
/// boot, so the time off isn't counted (conservative).
bool isRestart(ClockAnchor anchor, BootSnapshot snapshot) {
  final before = anchor.bootCount;
  final now = snapshot.bootCount;
  if (before != null && now != null) return before != now;
  return snapshot.elapsedRealtimeMs < anchor.anchorElapsedMs;
}

/// The anchor after a restart: the device clock, but never earlier than the
/// latest trusted time, so trusted time never goes back (FR-026).
ClockAnchor reanchor(
  ClockAnchor anchor,
  BootSnapshot snapshot,
  int deviceNowMs,
) => ClockAnchor(
  anchorMs: _max(deviceNowMs, anchor.latestTrustedMs),
  anchorElapsedMs: snapshot.elapsedRealtimeMs,
  bootCount: snapshot.bootCount,
  source: AnchorSource.device,
  latestTrustedMs: anchor.latestTrustedMs,
);

/// The anchor on the server's time (M06). Trusted time still never goes
/// below the latest recorded.
ClockAnchor serverAnchor(
  ClockAnchor anchor, {
  required int serverTimeMs,
  required int elapsedAtResponseMs,
  required int? bootCount,
}) => ClockAnchor(
  anchorMs: serverTimeMs,
  anchorElapsedMs: elapsedAtResponseMs,
  bootCount: bootCount,
  source: AnchorSource.server,
  latestTrustedMs: anchor.latestTrustedMs,
);

/// Trusted now while the phone hasn't restarted since [anchor].
int trustedNow(ClockAnchor anchor, int elapsedNowMs) => _max(
  anchor.latestTrustedMs,
  anchor.anchorMs + (elapsedNowMs - anchor.anchorElapsedMs),
);

/// Trusted now with no uptime channel: the device clock, never below the
/// latest trusted time.
int deviceTrustedNow(ClockAnchor anchor, int deviceNowMs) =>
    _max(anchor.latestTrustedMs, deviceNowMs);

int _max(int a, int b) => a > b ? a : b;
