// The economy's only time source (research R9, FR-025). Its anchor is read
// and written only through the store, which is the database's one writer.
import 'package:wassal/core/economy/domain/trusted_time.dart';
import 'package:wassal/core/economy/drift_economy_store.dart';
import 'package:wassal/core/platform/clock.dart';
import 'package:wassal/core/platform/uptime.dart';

abstract interface class TrustedClock {
  /// Trusted now, in UTC milliseconds. Synchronous, and never decreasing.
  int nowMs();

  /// Takes a fresh uptime reading: at startup, and on every return to the
  /// foreground, because the stopwatch between readings stops while the CPU
  /// sleeps.
  Future<void> resync();

  /// Anchors on the server's time (M06). [elapsedAtResponseMs] is the uptime
  /// counter when the response arrived.
  Future<void> anchorOnServer(
    int serverTimeMs, {
    required int elapsedAtResponseMs,
  });

  /// The uptime counter now, as [anchorOnServer] takes it: what the API
  /// client stamps a request and its answer with (M06, research R15).
  int elapsedMs();

  /// The latest trusted time handed out.
  int get latestMs;

  /// Stores [latestMs], as the app goes to the background.
  Future<void> saveLatest();
}

/// Trusted time from the stored anchor and the phone's uptime counter. The
/// device clock is read only to take a new anchor after a restart, or as the
/// whole clock when there is no uptime channel; either way never below the
/// latest trusted time.
final class UptimeTrustedClock implements TrustedClock {
  UptimeTrustedClock._({
    required this._uptime,
    required this._device,
    required this._store,
    required Stopwatch stopwatch,
    required ClockAnchor anchor,
    required this._snapshot,
  }) : _stopwatch = stopwatch..start(),
       _anchor = anchor,
       _latest = anchor.latestTrustedMs;

  /// Reads the stored anchor and re-anchors it when [snapshot], taken
  /// before the database opened, shows the phone restarted.
  static Future<UptimeTrustedClock> open({
    required UptimeSource uptime,
    required Clock device,
    required DriftEconomyStore store,
    required BootSnapshot? snapshot,
    Stopwatch Function() stopwatch = Stopwatch.new,
  }) async {
    var anchor = await store.loadAnchor();
    if (snapshot != null && isRestart(anchor, snapshot)) {
      anchor = reanchor(anchor, snapshot, _ms(device));
      await store.saveAnchor(anchor);
    }
    return UptimeTrustedClock._(
      uptime: uptime,
      device: device,
      store: store,
      stopwatch: stopwatch(),
      anchor: anchor,
      snapshot: snapshot,
    );
  }

  final UptimeSource _uptime;
  final Clock _device;
  final DriftEconomyStore _store;
  final Stopwatch _stopwatch;
  ClockAnchor _anchor;
  BootSnapshot? _snapshot;
  int _latest;

  static int _ms(Clock clock) => clock().millisecondsSinceEpoch;

  @override
  int nowMs() {
    final snapshot = _snapshot;
    final now = snapshot == null
        ? deviceTrustedNow(_anchor, _ms(_device))
        : trustedNow(
            _anchor,
            snapshot.elapsedRealtimeMs + _stopwatch.elapsedMilliseconds,
          );
    if (now > _latest) _latest = now;
    return _latest;
  }

  @override
  int get latestMs => _latest;

  /// The last reading plus the stopwatch since it. Without an uptime
  /// channel, the stopwatch alone: trusted time then follows the device
  /// clock, and the anchor isn't read.
  @override
  int elapsedMs() =>
      (_snapshot?.elapsedRealtimeMs ?? 0) + _stopwatch.elapsedMilliseconds;

  @override
  Future<void> resync() async {
    final snapshot = await _uptime.snapshot();
    final anchor = _anchor.withLatest(nowMs());
    final restarted = snapshot != null && isRestart(anchor, snapshot);
    // The new anchor and its reading change together, before the save, so a
    // failed save leaves memory consistent.
    if (restarted) _anchor = reanchor(anchor, snapshot, _ms(_device));
    _snapshot = snapshot;
    _stopwatch.reset();
    if (restarted) await _store.saveAnchor(_anchor);
  }

  @override
  Future<void> anchorOnServer(
    int serverTimeMs, {
    required int elapsedAtResponseMs,
  }) async {
    _anchor = serverAnchor(
      _anchor.withLatest(nowMs()),
      serverTimeMs: serverTimeMs,
      elapsedAtResponseMs: elapsedAtResponseMs,
      bootCount: _snapshot?.bootCount,
    );
    await _store.saveAnchor(_anchor);
  }

  @override
  Future<void> saveLatest() => _store.saveAnchor(_anchor.withLatest(nowMs()));
}
