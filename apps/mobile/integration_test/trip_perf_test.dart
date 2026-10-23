// The trip's frame rate, response and memory on a device
// (specs/008-m02-trip-screen SC-003 to SC-005, research R25): the real app,
// its frames driving the clock, the real character in every seat, playing a
// sample trip's 3-star run as it comes. CI doesn't run this; the owner runs
// it on the Galaxy A06 through the script, which prints the summary:
//
//   tool/perf/trip_fps.sh com.wassalogra.app.dev line_gamaa.02
import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'dart:ui' show FramePhase, FrameTiming;

import 'package:flame/game.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/bootstrap/app.dart';
import 'package:wassal/core/content/content_providers.dart';
import 'package:wassal/core/platform/connectivity.dart';
import 'package:wassal/core/routing/router.dart';
import 'package:wassal/features/trip/application/trip_controller.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';
import 'package:wassal/features/trip/presentation/dashboard/hand_slot.dart';
import 'package:wassal/features/trip/presentation/dashboard/tray.dart';
import 'package:wassal/features/trip/presentation/overlays/hit_areas.dart';
import 'package:wassal/features/trip/presentation/scene/trip_game.dart';

import '../test/helpers/content.dart';
import '../test/helpers/pump_app.dart';
import '../test/helpers/trip.dart';
import 'trip_helpers.dart';

/// The trip to play, from the script.
const _tripId = String.fromEnvironment(
  'WASSAL_PERF_TRIP',
  defaultValue: 'line_gamaa.02',
);

const _second = 1000000;

/// Collects every frame's timing while it runs.
final class _Frames {
  _Frames() {
    SchedulerBinding.instance.addTimingsCallback(_add);
  }

  final timings = <FrameTiming>[];
  final _waiting = <(int, Completer<FrameTiming>)>[];

  void _add(List<FrameTiming> batch) {
    timings.addAll(batch);
    for (final timing in batch) {
      final start = timing.timestampInMicroseconds(FramePhase.buildStart);
      _waiting.removeWhere((w) {
        if (start < w.$1) return false;
        w.$2.complete(timing);
        return true;
      });
    }
  }

  /// The first frame whose build starts at or after [micros] (the same
  /// clock as [Timeline.now]).
  Future<FrameTiming> after(int micros) {
    final done = Completer<FrameTiming>();
    _waiting.add((micros, done));
    return done.future;
  }

  void dispose() => SchedulerBinding.instance.removeTimingsCallback(_add);
}

int _raster(FrameTiming t) =>
    t.timestampInMicroseconds(FramePhase.rasterFinish);

/// Average fps, and the fewest frames in any one-second window.
({double average, int worstWindow}) _rates(List<FrameTiming> frames) {
  final ends = [for (final f in frames) _raster(f)]..sort();
  final span = ends.last - ends.first;
  var worst = ends.length;
  var j = 0;
  for (var i = 0; i < ends.length && ends[i] + _second <= ends.last; i++) {
    while (j < ends.length && ends[j] < ends[i] + _second) {
      j++;
    }
    worst = worst < j - i ? worst : j - i;
  }
  return (average: (ends.length - 1) * _second / span, worstWindow: worst);
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized()
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('$_tripId within the device budgets', (tester) async {
    await deleteAppDatabase();
    final fixture = loadFixture(
      'sample__${_tripId.replaceAll('.', '_')}_three_stars',
    );
    // The real app: no test fakes, so frames drive the clock and the
    // character draws the passengers. Only the network is off.
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          contentRemoteProvider.overrideWithValue(FakeContentRemote()),
          connectivitySourceProvider.overrideWithValue(
            FakeConnectivitySource(),
          ),
        ],
        child: const WassalApp(),
      ),
    );
    await pumpUntil(tester, () => currentLocation(tester) == '/home');
    final container = ProviderScope.containerOf(
      tester.element(find.byType(WassalApp)),
    );
    final frames = _Frames();
    addTearDown(frames.dispose);

    // The trip's first frame (SC-005).
    final openedAt = Timeline.now;
    container.read(routerProvider).go('/trip/$_tripId');
    await pumpUntil(
      tester,
      () =>
          find.byType(GameWidget<TripGame>).evaluate().isNotEmpty &&
          controllerOf(tester).phase == TripPhase.running,
    );
    final firstFrame = await frames.after(Timeline.now);
    final firstFrameMs = (_raster(firstFrame) - openedAt) / 1000;

    final c = controllerOf(tester);
    var peakRss = ProcessInfo.currentRss;
    final memory = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (ProcessInfo.currentRss > peakRss) peakRss = ProcessInfo.currentRss;
    });
    double? tapMs;
    final playedFrom = frames.timings.length;

    await binding.watchPerformance(() async {
      var next = 0;
      final log = fixture.commandLog;
      while (c.phase != TripPhase.ending && c.phase != TripPhase.ended) {
        if (c.phase == TripPhase.disputeOpen) {
          final asked = c.view!.choices.whereType<DisputeChoice>().first;
          c.answerDispute(asked.a);
        } else if (next < log.length && c.engine!.state.tMs >= log[next].tMs) {
          final command = log[next++].command;
          if (command is PickFromTray && tapMs == null) {
            // A drawer tap to the frame that shows the hand (SC-005).
            final tappedAt = Timeline.now;
            await _perform(tester, c, command);
            final shown = await frames.after(Timeline.now);
            tapMs = (_raster(shown) - tappedAt) / 1000;
          } else {
            await _perform(tester, c, command);
          }
        }
        await Future<void>.delayed(const Duration(milliseconds: 8));
      }
    }, reportKey: 'frame_summary');
    memory.cancel();
    // Let the last batch of timings arrive.
    await Future<void>.delayed(const Duration(seconds: 2));

    final played = frames.timings.sublist(playedFrom);
    final rates = _rates(played);
    binding.reportData = {
      ...?binding.reportData,
      'trip_perf': {
        'trip_id': _tripId,
        'frames': played.length,
        'average_fps': rates.average,
        'worst_window_fps': rates.worstWindow,
        'drawer_tap_to_hand_ms': tapMs,
        'first_frame_ms': firstFrameMs,
        'peak_rss_mb': peakRss / (1024 * 1024),
      },
    };
  });
}

/// [command] through the screen's controls where they exist.
Future<void> _perform(
  WidgetTester tester,
  TripController c,
  Command command,
) async {
  switch (command) {
    case PickFromTray(:final denomination):
      await tester.tap(find.byKey(Tray.slotKey(denomination)));
    case ReturnHand():
      await tester.tap(find.byKey(HandSlot.slotKey));
    case SendHand(:final passengerId) || Tap(:final passengerId):
      await tester.tap(
        find.byKey(HitAreas.keyOf(passengerId)),
        warnIfMissed: false,
      );
    case _:
      await playCommands(c, [LoggedCommand(c.engine!.state.tMs, command)]);
  }
}
