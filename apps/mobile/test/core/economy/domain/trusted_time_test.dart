import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/economy/domain/trusted_time.dart';

// The trusted-time arithmetic, case by case
// (contracts/fuel-and-time.md "Cases the tests cover").

const _t0 = 1792627200000;
const _hour = 3600000;
const _minute = 60000;

/// The anchor of a first open at [_t0], one hour after boot 7.
ClockAnchor _anchor() => firstAnchor(
  const BootSnapshot(elapsedRealtimeMs: _hour, bootCount: 7),
  _t0,
);

/// What the clock reads after [snapshot], with [deviceMs] on the device.
int _after(ClockAnchor anchor, BootSnapshot snapshot, int deviceMs) {
  final current = isRestart(anchor, snapshot)
      ? reanchor(anchor, snapshot, deviceMs)
      : anchor;
  return trustedNow(current, snapshot.elapsedRealtimeMs);
}

void main() {
  test('the first anchor is the device clock at the first open', () {
    final anchor = _anchor();
    expect(anchor.anchorMs, _t0);
    expect(anchor.anchorElapsedMs, _hour);
    expect(anchor.bootCount, 7);
    expect(anchor.source, AnchorSource.device);
    expect(anchor.latestTrustedMs, _t0);
    expect(firstAnchor(null, _t0).anchorElapsedMs, 0);
  });

  test('time counts with the uptime counter', () {
    expect(trustedNow(_anchor(), _hour + 5 * _minute), _t0 + 5 * _minute);
  });

  group('the phone stays on', () {
    const later = BootSnapshot(
      elapsedRealtimeMs: _hour + 10 * _minute,
      bootCount: 7,
    );

    test('clock +3 h, app open or closed and reopened: nothing changes', () {
      expect(isRestart(_anchor(), later), isFalse);
      expect(
        _after(_anchor(), later, _t0 + 10 * _minute + 3 * _hour),
        _t0 + 10 * _minute,
      );
    });

    test('clock −3 h: nothing changes', () {
      expect(
        _after(_anchor(), later, _t0 + 10 * _minute - 3 * _hour),
        _t0 + 10 * _minute,
      );
    });

    test('a time zone change: nothing changes, every time is UTC', () {
      final local = DateTime.fromMillisecondsSinceEpoch(_t0);
      expect(local.millisecondsSinceEpoch, _t0);
      expect(_after(_anchor(), later, _t0 + 10 * _minute), _t0 + 10 * _minute);
    });
  });

  group('the phone restarts', () {
    const restarted = BootSnapshot(elapsedRealtimeMs: _minute, bootCount: 8);

    test('clock right, 2 h off: the 2 h count', () {
      expect(isRestart(_anchor(), restarted), isTrue);
      expect(_after(_anchor(), restarted, _t0 + 2 * _hour), _t0 + 2 * _hour);
    });

    test('clock +3 h: the 3 h count on the device', () {
      expect(_after(_anchor(), restarted, _t0 + 3 * _hour), _t0 + 3 * _hour);
    });

    test('clock −3 h: re-anchored at the latest, nothing taken away', () {
      final latest = _anchor().withLatest(_t0 + 30 * _minute);
      final anchor = reanchor(latest, restarted, _t0 - 3 * _hour);
      expect(anchor.anchorMs, _t0 + 30 * _minute);
      expect(trustedNow(anchor, _minute), _t0 + 30 * _minute);
      expect(trustedNow(anchor, 21 * _minute), _t0 + 50 * _minute);
    });

    test('no boot count and a longer uptime: treated as the same boot', () {
      final anchor = firstAnchor(
        const BootSnapshot(elapsedRealtimeMs: _hour),
        _t0,
      );
      const longer = BootSnapshot(elapsedRealtimeMs: 2 * _hour);
      expect(isRestart(anchor, longer), isFalse);
      // Only the uptime difference counts, not the real time off.
      expect(_after(anchor, longer, _t0 + 5 * _hour), _t0 + _hour);
    });

    test('no boot count and a shorter uptime: a restart', () {
      final anchor = firstAnchor(
        const BootSnapshot(elapsedRealtimeMs: _hour),
        _t0,
      );
      expect(
        isRestart(anchor, const BootSnapshot(elapsedRealtimeMs: _minute)),
        isTrue,
      );
    });
  });

  test('no channel: the device clock, never below the latest', () {
    final anchor = _anchor().withLatest(_t0 + _hour);
    expect(deviceTrustedNow(anchor, _t0 + 2 * _hour), _t0 + 2 * _hour);
    expect(deviceTrustedNow(anchor, _t0 - _hour), _t0 + _hour);
  });

  test('the latest trusted time never decreases', () {
    final anchor = _anchor().withLatest(_t0 + _hour);
    expect(anchor.withLatest(_t0).latestTrustedMs, _t0 + _hour);
    expect(trustedNow(anchor, 0), _t0 + _hour);
  });

  test('a server anchor never goes below the latest', () {
    final anchor = serverAnchor(
      _anchor().withLatest(_t0 + _hour),
      serverTimeMs: _t0,
      elapsedAtResponseMs: _hour,
      bootCount: 7,
    );
    expect(anchor.source, AnchorSource.server);
    expect(trustedNow(anchor, _hour + _minute), _t0 + _hour);
    expect(trustedNow(anchor, 3 * _hour), _t0 + 2 * _hour);
  });
}
