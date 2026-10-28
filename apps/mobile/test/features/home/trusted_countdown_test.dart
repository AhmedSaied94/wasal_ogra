// Time left on trusted time (specs/013-m08-home-result, research R11,
// SC-003): the device clock never moves it, only the countdown's text
// ticks, the screen reader's minutes change at most once a minute, and the
// timers stop with the widget.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/economy/economy_providers.dart';
import 'package:wassal/core/economy/trusted_clock.dart';
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/l10n/number_formatter.dart';
import 'package:wassal/features/home/presentation/trusted_countdown.dart';

import '../../helpers/home.dart';

/// Trusted time that only the test moves; [device] is the phone's clock,
/// which the widgets must never read.
final class _Clock implements TrustedClock {
  int now = 1000000;
  int device = 1000000;

  @override
  int nowMs() => now;

  @override
  int get latestMs => now;

  @override
  int elapsedMs() => now;

  @override
  Future<void> resync() async {}

  @override
  Future<void> anchorOnServer(
    int serverTimeMs, {
    required int elapsedAtResponseMs,
  }) async {}

  @override
  Future<void> saveLatest() async {}
}

const _minute = Duration.millisecondsPerMinute;

const _second = Duration.millisecondsPerSecond;

Future<void> _pump(WidgetTester tester, _Clock clock, Widget child) async {
  final container = ProviderContainer(
    overrides: [
      trustedClockProvider.overrideWith((ref) async => clock),
      numberFormatterProvider.overrideWithValue(
        const NumberFormatter(DigitStyle.western),
      ),
    ],
  );
  addTearDown(container.dispose);
  // Loaded before Home ever builds, as startup loads it.
  await container.read(trustedClockProvider.future);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: Directionality(textDirection: TextDirection.rtl, child: child),
    ),
  );
}

/// Counts its own builds.
class _Counted extends StatelessWidget {
  const _Counted(this.builds, this.child);

  final List<int> builds;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    builds.add(1);
    return child;
  }
}

void main() {
  test('minutes left round up, and stop at 0', () {
    expect(minutesLeft(13 * _minute, 0), 13);
    expect(minutesLeft(12 * _minute + 1, 0), 13);
    expect(minutesLeft(1, 0), 1);
    expect(minutesLeft(0, 0), 0);
    expect(minutesLeft(0, 5), 0);
  });

  testWidgets('the text follows trusted time, never the device clock', (
    tester,
  ) async {
    final clock = _Clock();
    final until = clock.now + 12 * _minute + 30 * _second;
    await _pump(
      tester,
      clock,
      TrustedCountdown(untilMs: until, style: const TextStyle()),
    );
    expect(shows('12:30'), findsOneWidget);

    // The phone's clock jumps an hour either way: nothing changes.
    for (final jump in [
      Duration.millisecondsPerHour,
      -2 * Duration.millisecondsPerHour,
    ]) {
      clock.device += jump;
      await tester.pump(countdownTick);
      expect(shows('12:30'), findsOneWidget);
    }

    clock.now += 31 * _second;
    await tester.pump(countdownTick);
    expect(shows('11:59'), findsOneWidget);

    clock.now = until + _minute;
    await tester.pump(countdownTick);
    expect(shows('0:00'), findsOneWidget);
  });

  testWidgets('a template wraps the time', (tester) async {
    final clock = _Clock();
    await _pump(
      tester,
      clock,
      TrustedCountdown(
        untilMs: clock.now + 90 * _second,
        style: const TextStyle(),
        template: (time) => 'next $time',
      ),
    );
    expect(shows('next 1:30'), findsOneWidget);
  });

  testWidgets('only the countdown rebuilds as it ticks', (tester) async {
    final clock = _Clock();
    final builds = <int>[];
    await _pump(
      tester,
      clock,
      _Counted(
        builds,
        TrustedCountdown(
          untilMs: clock.now + 10 * _minute,
          style: const TextStyle(),
        ),
      ),
    );
    final before = builds.length;
    for (var i = 0; i < 5; i++) {
      clock.now += _second;
      await tester.pump(countdownTick);
    }
    expect(builds.length, before);
    expect(shows('9:55'), findsOneWidget);
  });

  testWidgets('the ticking text is hidden from screen readers', (tester) async {
    final semantics = tester.ensureSemantics();
    final clock = _Clock();
    await _pump(
      tester,
      clock,
      TrustedCountdown(untilMs: clock.now + _minute, style: const TextStyle()),
    );
    expect(find.bySemanticsLabel('1:00'), findsNothing);
    semantics.dispose();
  });

  testWidgets('the minutes rebuild at most once a minute, rounded up', (
    tester,
  ) async {
    final clock = _Clock();
    final seen = <int>[];
    await _pump(
      tester,
      clock,
      TrustedMinutes(
        untilMs: clock.now + 2 * _minute + 30 * _second,
        builder: (context, minutes) {
          seen.add(minutes);
          return Text('$minutes');
        },
      ),
    );
    expect(seen, [3]);
    // 75 one-second ticks: 2:30 → 1:15 crosses two minute marks.
    for (var i = 0; i < 75; i++) {
      clock.now += _second;
      await tester.pump(countdownTick);
    }
    expect(seen, [3, 2]);
    expect(shows('2'), findsOneWidget);
    for (var i = 0; i < 75; i++) {
      clock.now += _second;
      await tester.pump(countdownTick);
    }
    expect(seen, [3, 2, 1, 0]);
  });

  testWidgets('the timers stop with the widgets', (tester) async {
    final clock = _Clock();
    await _pump(
      tester,
      clock,
      Column(
        children: [
          TrustedCountdown(
            untilMs: clock.now + _minute,
            style: const TextStyle(),
          ),
          TrustedMinutes(
            untilMs: clock.now + _minute,
            builder: (_, minutes) => Text('m$minutes'),
          ),
        ],
      ),
    );
    await tester.pumpWidget(const SizedBox());
    // A periodic timer left running fails the test here.
    expect(tester.binding.transientCallbackCount, 0);
  });
}
