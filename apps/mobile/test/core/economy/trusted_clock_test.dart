import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/economy/domain/trusted_time.dart';

import '../../helpers/economy.dart';

// UptimeTrustedClock over the fakes and a real store on a temp file
// (contracts/fuel-and-time.md "Trusted time"). The clock reads and writes
// its anchor only through the store.

const _hour = Duration(hours: 1);
const _hourMs = 3600000;
const _minuteMs = 60000;

Future<TestEconomy> _open({FakeUptimeSource? uptime}) =>
    testEconomy(dbFile: tempDbFile(), uptime: uptime);

/// Leaves the app, as on the way to the background, then opens it again.
Future<TestEconomy> _relaunch(TestEconomy economy) async {
  await economy.clock.saveLatest();
  return reopen(economy);
}

void main() {
  test('the first open anchors on the device clock', () async {
    final economy = await _open();
    expect(economy.clock.nowMs(), testEpochMs);
    final anchor = await economy.store.loadAnchor();
    expect(anchor.source, AnchorSource.device);
    expect(anchor.anchorMs, testEpochMs);
    expect(anchor.anchorElapsedMs, testBootElapsedMs);
    expect(anchor.bootCount, 1);
    expect(anchor.latestTrustedMs, testEpochMs);
  });

  test('time follows the uptime counter while the app is open', () async {
    final economy = await _open();
    economy.passTime(minute * 10);
    expect(economy.clock.nowMs(), testEpochMs + 10 * _minuteMs);
  });

  group('same boot', () {
    for (final (name, shift) in [('+3 h', _hour * 3), ('−3 h', -(_hour * 3))]) {
      test('the device clock moved $name: uptime decides', () async {
        var economy = await _open();
        economy.passTime(minute * 10);
        // While open: no effect.
        economy.device.advance(shift);
        expect(economy.clock.nowMs(), testEpochMs + 10 * _minuteMs);

        // Closed and reopened on the same boot: still none.
        economy = await _relaunch(economy);
        expect(economy.clock.nowMs(), testEpochMs + 10 * _minuteMs);
        expect((await economy.store.loadAnchor()).anchorMs, testEpochMs);
      });
    }
  });

  group('restart', () {
    test('a new boot count re-anchors on the device clock', () async {
      var economy = await _open();
      economy.passTime(minute * 30);
      economy
        ..uptime.restart()
        ..device.advance(_hour * 2);

      economy = await _relaunch(economy);
      const expected = testEpochMs + 30 * _minuteMs + 2 * _hourMs;
      expect(economy.clock.nowMs(), expected);
      final anchor = await economy.store.loadAnchor();
      expect(anchor.anchorMs, expected);
      expect(anchor.anchorElapsedMs, _minuteMs);
      expect(anchor.bootCount, 2);
      expect(anchor.source, AnchorSource.device);
    });

    test('a device clock behind the latest re-anchors at the latest', () async {
      var economy = await _open();
      economy.passTime(minute * 30);
      final latest = economy.clock.nowMs();
      economy.uptime.restart();
      economy.device.nowMs = testEpochMs - 3 * _hourMs;

      economy = await _relaunch(economy);
      expect(economy.clock.nowMs(), latest);
      economy.passTime(minute * 10);
      expect(economy.clock.nowMs(), latest + 10 * _minuteMs);
    });
  });

  test(
    'resync() takes a new reading, as on a return to the foreground',
    () async {
      final economy = await _open();
      // The CPU sleeps: the counter moves, the stopwatch doesn't.
      economy.uptime.sleep(minute * 20);
      expect(economy.clock.nowMs(), testEpochMs);

      await economy.clock.resync();
      expect(economy.clock.nowMs(), testEpochMs + 20 * _minuteMs);
      economy.passTime(minute);
      expect(economy.clock.nowMs(), testEpochMs + 21 * _minuteMs);
    },
  );

  test('resync() after a restart while open re-anchors', () async {
    final economy = await _open();
    economy.passTime(minute * 5);
    economy
      ..uptime.restart()
      ..device.advance(_hour);
    await economy.clock.resync();
    expect(economy.clock.nowMs(), testEpochMs + 5 * _minuteMs + _hourMs);
    expect((await economy.store.loadAnchor()).bootCount, 2);
  });

  test('saveLatest() stores the latest time, which never decreases', () async {
    final economy = await _open();
    economy.passTime(minute * 5);
    final now = economy.clock.nowMs();
    expect(economy.clock.latestMs, now);
    await economy.clock.saveLatest();
    final stored = await economy.store.loadAnchor();
    expect(stored.latestTrustedMs, now);

    // A save with an older latest keeps the stored one.
    await economy.store.saveAnchor(
      ClockAnchor(
        anchorMs: stored.anchorMs,
        anchorElapsedMs: stored.anchorElapsedMs,
        bootCount: stored.bootCount,
        source: stored.source,
        latestTrustedMs: testEpochMs,
      ),
    );
    expect((await economy.store.loadAnchor()).latestTrustedMs, now);
  });

  test(
    'anchorOnServer() sets the server as source, never below the latest',
    () async {
      final economy = await _open();
      economy.passTime(minute * 10);

      await economy.clock.anchorOnServer(
        testEpochMs + _hourMs,
        elapsedAtResponseMs: economy.uptime.elapsedRealtimeMs,
      );
      expect(economy.clock.nowMs(), testEpochMs + _hourMs);
      final anchor = await economy.store.loadAnchor();
      expect(anchor.source, AnchorSource.server);
      expect(anchor.anchorMs, testEpochMs + _hourMs);

      // A server time behind what was handed out moves nothing back.
      await economy.clock.anchorOnServer(
        testEpochMs,
        elapsedAtResponseMs: economy.uptime.elapsedRealtimeMs,
      );
      expect(economy.clock.nowMs(), testEpochMs + _hourMs);
      economy.passTime(minute * 30);
      expect(economy.clock.nowMs(), testEpochMs + _hourMs);
      economy.passTime(minute * 40);
      expect(economy.clock.nowMs(), testEpochMs + _hourMs + 10 * _minuteMs);
    },
  );

  test('no channel: the device clock, never below the latest', () async {
    final economy = await _open(uptime: FakeUptimeSource(available: false));
    expect(economy.clock.nowMs(), testEpochMs);
    expect((await economy.store.loadAnchor()).anchorElapsedMs, 0);

    economy.device.advance(_hour);
    expect(economy.clock.nowMs(), testEpochMs + _hourMs);
    economy.device.nowMs = testEpochMs;
    expect(economy.clock.nowMs(), testEpochMs + _hourMs);
  });
}
