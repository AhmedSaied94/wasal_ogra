// The scenes' frame rate and memory on a device (specs/012.5-m22-animated-
// scenes SC-002, research R14): the real app on a fresh install, with both
// Rive files, playing the opening and then the سلمى scene, each panel's turns
// to their end before «يلا». CI doesn't run this; the owner runs it on the
// Galaxy A06 through the script, which prints the summary:
//
//   tool/perf/scene_fps.sh com.wassalogra.app.dev
import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'dart:ui' show FrameTiming;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rive/rive.dart' as rive;
import 'package:wassal/bootstrap/app.dart';
import 'package:wassal/core/content/content_providers.dart';
import 'package:wassal/core/platform/connectivity.dart';
import 'package:wassal/core/routing/router.dart';
import 'package:wassal/core/theme/components/story.dart';
import 'package:wassal/features/onboarding/presentation/scene_player.dart';

import '../test/helpers/content.dart';
import '../test/helpers/pump_app.dart';
import 'frame_rates.dart';
import 'trip_helpers.dart';

/// Past the longest panel's turns (`opening_stand`, 4000 ms) and its slide.
const _turnsEnd = Duration(milliseconds: 4600);

/// The page dots' panel, or null once the scene has left.
int? _panel(WidgetTester tester) {
  final dots = find.byType(PageDots).evaluate();
  return dots.isEmpty ? null : (dots.first.widget as PageDots).index;
}

/// Waits in real time, the frames running by themselves, until [done].
Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 200 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  expect(done(), isTrue);
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized()
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('the opening and the_stand within the device budgets', (
    tester,
  ) async {
    await deleteAppDatabase();
    // The real app: no test fakes, so both Rive files load and frames drive
    // the clock. Only the network is off.
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
    await pumpUntil(
      tester,
      () => currentLocation(tester) == '/onboarding/intro',
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(WassalApp)),
    );
    final frames = FrameTimings();
    addTearDown(frames.dispose);
    var peakRss = ProcessInfo.currentRss;
    final memory = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (ProcessInfo.currentRss > peakRss) peakRss = ProcessInfo.currentRss;
    });

    var panels = 0;
    var animated = 0;
    final spans = <(int, int)>[];

    /// The scene on screen, panel by panel, until it leaves.
    Future<void> play() async {
      final scene = currentLocation(tester);
      final from = Timeline.now;
      while (currentLocation(tester) == scene) {
        final shown = _panel(tester);
        await Future<void>.delayed(_turnsEnd);
        panels++;
        final art = find.descendant(
          of: find.byKey(ScenePlayer.panelKey),
          matching: find.byType(rive.RiveWidget),
        );
        if (art.evaluate().isNotEmpty) animated++;
        await tester.tap(find.byKey(ScenePlayer.nextKey));
        await _until(
          () => currentLocation(tester) != scene || _panel(tester) != shown,
        );
      }
      spans.add((from, Timeline.now));
    }

    await binding.watchPerformance(() async {
      await play();
      container
          .read(routerProvider)
          .go('/onboarding/scene/the_stand?then=/home');
      await _until(
        () => currentLocation(tester).startsWith('/onboarding/scene/the_stand'),
      );
      await play();
    }, reportKey: 'frame_summary');
    memory.cancel();
    // Let the last batch of timings arrive.
    await Future<void>.delayed(const Duration(seconds: 2));

    // Each scene on its own: the Name card between them draws no frames.
    final scenes = [
      for (final (from, to) in spans)
        [
          for (final FrameTiming t in frames.timings)
            if (rasterEnd(t) >= from && rasterEnd(t) <= to) t,
        ],
    ];
    expect(scenes, hasLength(2));
    for (final (i, played) in scenes.indexed) {
      expect(played.length, greaterThan(1), reason: 'scene ${i + 1} frames');
    }
    final rates = [for (final played in scenes) frameRates(played)];
    binding.reportData = {
      ...?binding.reportData,
      'scene_perf': {
        'scenes': ['opening', 'the_stand'],
        'panels': panels,
        'animated_panels': animated,
        'frames': frames.timings.length,
        'average_fps': rates.map((r) => r.average).reduce(_min),
        'worst_window_fps': rates.map((r) => r.worstWindow).reduce(_min),
        'peak_rss_mb': peakRss / (1024 * 1024),
      },
    };
  });
}

T _min<T extends num>(T a, T b) => a < b ? a : b;
