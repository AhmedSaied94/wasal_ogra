// The story viewer (specs/015-m10-apartment-story, contracts/scene-viewer.md
// "The viewer", "Taps", T079): the top bar, the bubbles' sides and the
// narrator's caption, the driver's name, the dots and the last panel's
// buttons, a sequence moving on, skip and back recording what was reached,
// `then`, an unknown or locked scene, reduced motion and the announcement.
import 'package:content_models/content_models.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/bootstrap/app.dart' show appLocale;
import 'package:wassal/core/economy/domain/economy_state.dart';
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/core/l10n/number_formatter.dart';
import 'package:wassal/core/economy/economy_providers.dart';
import 'package:wassal/core/economy/domain/op.dart' show OpType;
import 'package:wassal/core/theme/components/story.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/onboarding/onboarding_providers.dart';
import 'package:wassal/features/story/presentation/scene_panel_view.dart';
import 'package:wassal/features/story/presentation/scene_viewer_page.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

import '../../helpers/first_session.dart';
import '../../helpers/lines.dart';
import '../../helpers/progress.dart';

/// `line_hay.03` finished: «المعلم»'s story trip, so `the_stand` is unlocked.
const _stand = {'line_hay.03': 1};

late AppLocalizations _l10n;

Future<ProviderContainer> _open(
  WidgetTester tester,
  String location, {
  EconomyState Function(int nowMs)? state,
  bool reduced = false,
  bool settle = true,
  List<Override> overrides = const [],
}) async {
  if (reduced) {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  }
  final (container, _) = await pumpLinesApp(
    tester,
    pack: samplePackJsonForLines(),
    location: location,
    state: state ?? playerState(),
    settle: settle,
    overrides: overrides,
  );
  return container;
}

Scene _scene(String id) {
  final content = sampleWith((_) {});
  for (final chapter in content.chapters) {
    for (final scene in chapter.scenes) {
      if (scene.sceneId == id) return scene;
    }
  }
  throw StateError(id);
}

/// A tap on the panel, once its bubbles have all shown.
Future<void> _next(WidgetTester tester) async {
  await tester.tap(find.byKey(SceneViewerPage.panelKey));
  await tester.pumpAndSettle();
}

/// Taps to the scene's last panel.
Future<void> _toLast(WidgetTester tester, int panels) async {
  for (var i = 1; i < panels; i++) {
    await _next(tester);
  }
}

/// Which dot is the long one, by the dots' widths.
int _activeDot(WidgetTester tester, int count) {
  for (var i = 0; i < count; i++) {
    if (tester.getSize(find.byKey(PageDots.dotKey(i))).width > 20) return i;
  }
  return -1;
}

Set<String> _seen(ProviderContainer container, String chapter) =>
    container.read(economyViewProvider).scenesSeen[chapter] ?? const {};

void main() {
  setUpAll(() async {
    _l10n = await AppLocalizations.delegate.load(appLocale);
  });

  testWidgets('the top bar: the chapter label over the scene title, and '
      '«تخطّى»', (tester) async {
    await _open(tester, '/story/scene/opening');
    const numbers = NumberFormatter(DigitStyle.arabicIndic);
    expect(
      find.text(_l10n.sceneViewerChapterLabel(numbers.integer(1))),
      findsOneWidget,
    );
    expect(find.text(_scene('opening').title.arEg), findsOneWidget);
    expect(find.byKey(SceneViewerPage.skipKey), findsOneWidget);
    expect(
      tester.getSize(find.byKey(SceneViewerPage.skipKey)).height,
      greaterThanOrEqualTo(LayoutTokens.touchMin),
    );
  });

  testWidgets('a narrator is the caption, with the speaker\'s bubble under '
      'it', (tester) async {
    await _open(tester, '/story/scene/opening');
    expect(find.byKey(ScenePanelView.captionKey), findsOneWidget);
    expect(find.byKey(ScenePanelView.bubbleKey(0)), findsOneWidget);
    expect(find.byKey(ScenePanelView.bubbleKey(1)), findsNothing);
    expect(find.text(_l10n.sceneSpeaker('moallem')), findsOneWidget);
  });

  testWidgets('two speakers: the first bubble at the start side, the '
      'second at the end, the driver by name', (tester) async {
    await _open(tester, '/story/scene/opening');
    await _next(tester);
    final first = tester.getRect(find.byKey(ScenePanelView.bubbleKey(0)));
    final second = tester.getRect(find.byKey(ScenePanelView.bubbleKey(1)));
    final panel = tester.getRect(find.byKey(SceneViewerPage.panelKey));
    // RTL: the start is the right.
    expect(first.center.dx, greaterThan(panel.center.dx));
    expect(second.center.dx, lessThan(panel.center.dx));
    expect(first.top, lessThan(second.top));
    expect(first.width, 190);
    expect(second.width, 180);
    // Inside the panel.
    expect(panel.contains(first.topLeft), isTrue);
    expect(panel.contains(second.bottomRight), isTrue);
    expect(find.text('أحمد'), findsOneWidget);
  });

  testWidgets('a player without a name is «الأسطى»', (tester) async {
    await _open(
      tester,
      '/story/scene/opening',
      state: (nowMs) => EconomyState.newPlayer(fuelMax: 5, nowMs: nowMs),
    );
    await _next(tester);
    expect(find.text(_l10n.driverNameDefault), findsOneWidget);
  });

  testWidgets('the dots, and the last panel\'s buttons only on the last', (
    tester,
  ) async {
    await _open(tester, '/story/scene/opening');
    final panels = _scene('opening').panels.length;
    expect(find.byType(PageDots), findsOneWidget);
    expect(_activeDot(tester, panels), 0);
    expect(find.byKey(SceneViewerPage.continueKey), findsNothing);
    expect(find.byKey(SceneViewerPage.shareKey), findsNothing);

    await _next(tester);
    expect(_activeDot(tester, panels), 1);
    expect(find.byKey(SceneViewerPage.continueKey), findsNothing);

    await _toLast(tester, panels - 1);
    expect(_activeDot(tester, panels), panels - 1);
    expect(find.byKey(SceneViewerPage.continueKey), findsOneWidget);
    expect(find.byKey(SceneViewerPage.shareKey), findsOneWidget);
    final share = tester.getSize(find.byKey(SceneViewerPage.shareKey));
    final go = tester.getSize(find.byKey(SceneViewerPage.continueKey));
    expect(share.height, 64);
    expect(go.height, 64);
    expect(go.width, greaterThan(share.width));

    // A tap on the last panel does nothing.
    await _next(tester);
    expect(_activeDot(tester, panels), panels - 1);
  });

  testWidgets('a tap while the bubbles are still appearing shows them all, '
      'the next moves on', (tester) async {
    await _open(tester, '/story/scene/opening', settle: false);
    final arts = [for (final p in _scene('opening').panels) p.art];
    // The panel on screen: the newest while one slides out.
    int shown() => arts.indexOf(
      tester
          .widgetList<ScenePanelView>(find.byType(ScenePanelView))
          .last
          .panel
          .art,
    );
    // The first panel's bubble has shown; on to the two-speaker panel,
    // whose second bubble comes last.
    await tester.tap(find.byKey(SceneViewerPage.panelKey));
    await tester.pump(const Duration(milliseconds: 20));
    expect(shown(), 1);
    await tester.pump(const Duration(milliseconds: 20));
    // Still arriving: this tap finishes the reveal, not the panel.
    await tester.tap(find.byKey(SceneViewerPage.panelKey));
    await tester.pump(const Duration(milliseconds: 20));
    expect(shown(), 1);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(SceneViewerPage.panelKey));
    await tester.pumpAndSettle();
    expect(shown(), 2);
  });

  testWidgets('«كمّل» on the last panel records the scene and leaves to the '
      'apartment', (tester) async {
    final container = await _open(tester, '/story/scene/opening');
    await _toLast(tester, _scene('opening').panels.length);
    await tester.tap(find.byKey(SceneViewerPage.continueKey));
    await tester.pumpAndSettle();
    expect(locationOf(container), '/apartment');
    expect(_seen(container, 'ch1_first_job'), {'opening'});
  });

  testWidgets('reaching the last panel records the scene before «كمّل»', (
    tester,
  ) async {
    final container = await _open(tester, '/story/scene/opening');
    await _toLast(tester, _scene('opening').panels.length);
    await tester.pumpAndSettle();
    expect(_seen(container, 'ch1_first_job'), {'opening'});
    expect(find.byKey(SceneViewerPage.continueKey), findsOneWidget);
  });

  testWidgets('a chapter plays its unlocked scenes one after another, the '
      'dots starting again', (tester) async {
    final container = await _open(
      tester,
      '/story/ch1_first_job',
      state: playerState(stars: _stand),
    );
    final opening = _scene('opening');
    final stand = _scene('the_stand');
    expect(find.text(opening.title.arEg), findsOneWidget);
    await _toLast(tester, opening.panels.length);
    await tester.tap(find.byKey(SceneViewerPage.continueKey));
    await tester.pumpAndSettle();
    // The second scene, from its first panel.
    expect(find.text(stand.title.arEg), findsOneWidget);
    expect(_activeDot(tester, stand.panels.length), 0);
    expect(find.byKey(SceneViewerPage.continueKey), findsNothing);
    expect(_seen(container, 'ch1_first_job'), {'opening'});

    await _toLast(tester, stand.panels.length);
    await tester.tap(find.byKey(SceneViewerPage.continueKey));
    await tester.pumpAndSettle();
    expect(locationOf(container), '/apartment');
    expect(_seen(container, 'ch1_first_job'), {'opening', 'the_stand'});
  });

  testWidgets('«تخطّى» halfway records the scene reached and goes to '
      '`then`', (tester) async {
    final container = await _open(tester, '/story/scene/opening?then=/home');
    await _next(tester);
    await tester.tap(find.byKey(SceneViewerPage.skipKey));
    await tester.pumpAndSettle();
    expect(locationOf(container), '/home');
    expect(_seen(container, 'ch1_first_job'), {'opening'});
  });

  testWidgets('skip in a sequence records every scene reached so far, and '
      'not the next', (tester) async {
    final container = await _open(
      tester,
      '/story/ch1_first_job',
      state: playerState(stars: _stand),
    );
    await _toLast(tester, _scene('opening').panels.length);
    await tester.tap(find.byKey(SceneViewerPage.continueKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(SceneViewerPage.skipKey));
    await tester.pumpAndSettle();
    expect(_seen(container, 'ch1_first_job'), {'opening', 'the_stand'});
    expect(locationOf(container), '/apartment');
  });

  testWidgets('system back records and leaves as «تخطّى» does', (tester) async {
    final container = await _open(
      tester,
      '/story/scene/opening?then=/story/album',
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(_seen(container, 'ch1_first_job'), {'opening'});
    expect(locationOf(container), '/story/album');
  });

  testWidgets('a second tap on «كمّل» while it records does nothing: the '
      'next scene, not past the end', (tester) async {
    final container = await _open(
      tester,
      '/story/ch1_first_job',
      state: playerState(stars: _stand),
    );
    final stand = _scene('the_stand');
    await _toLast(tester, _scene('opening').panels.length);
    // Both taps land before the record finishes.
    await tester.tap(find.byKey(SceneViewerPage.continueKey));
    await tester.tap(find.byKey(SceneViewerPage.continueKey));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text(stand.title.arEg), findsOneWidget);
    expect(_activeDot(tester, stand.panels.length), 0);
    expect(_seen(container, 'ch1_first_job'), {'opening'});
  });

  testWidgets('a failed write is reported, and «تخطّى» still leaves', (
    tester,
  ) async {
    final container = await _open(
      tester,
      '/story/scene/opening?then=/story/album',
      overrides: [
        firstSessionFlagsProvider.overrideWith(
          () => FailingFlags({'sceneSeen'}),
        ),
      ],
    );
    await tester.tap(find.byKey(SceneViewerPage.skipKey));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isA<Exception>());
    expect(locationOf(container), '/story/album');
  });

  testWidgets('a failed write is reported, and «كمّل» still leaves', (
    tester,
  ) async {
    // The write the last panel starts fails; «كمّل» writes again and leaves.
    final container = await _open(
      tester,
      '/story/scene/opening?then=/story/album',
      overrides: [
        firstSessionFlagsProvider.overrideWith(
          () => FailingFlags({'sceneSeen'}),
        ),
      ],
    );
    await _toLast(tester, _scene('opening').panels.length);
    expect(tester.takeException(), isA<Exception>());
    await tester.tap(find.byKey(SceneViewerPage.continueKey));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(locationOf(container), '/story/album');
    expect(_seen(container, 'ch1_first_job'), {'opening'});
  });

  testWidgets('a replay stores no operation', (tester) async {
    final (container, economy) = await pumpLinesApp(
      tester,
      pack: samplePackJsonForLines(),
      location: '/story/scene/opening',
      state: playerState(
        scenesSeen: const {
          'ch1_first_job': {'opening'},
        },
      ),
    );
    Future<int> stored() async => (await economy.service.pendingOps())
        .where((entry) => entry.op.type == OpType.storyProgress)
        .length;
    final before = await tester.runAsync(stored);
    await _toLast(tester, _scene('opening').panels.length);
    await tester.tap(find.byKey(SceneViewerPage.continueKey));
    await tester.pumpAndSettle();
    expect(await tester.runAsync(stored), before);
    expect(_seen(container, 'ch1_first_job'), {'opening'});
  });

  testWidgets('a first view stores one story_progress per scene', (
    tester,
  ) async {
    final (_, economy) = await pumpLinesApp(
      tester,
      pack: samplePackJsonForLines(),
      location: '/story/scene/opening',
    );
    await _toLast(tester, _scene('opening').panels.length);
    await tester.tap(find.byKey(SceneViewerPage.continueKey));
    await tester.pumpAndSettle();
    final ops = await tester.runAsync(economy.service.pendingOps);
    expect(
      ops!.where((entry) => entry.op.type == OpType.storyProgress),
      hasLength(1),
    );
  });

  testWidgets('an unknown scene goes to `then`, else the apartment', (
    tester,
  ) async {
    final container = await _open(tester, '/story/scene/nope?then=/home');
    expect(locationOf(container), '/home');
  });

  testWidgets('an unknown scene without `then` goes to the apartment', (
    tester,
  ) async {
    final container = await _open(tester, '/story/scene/nope');
    expect(locationOf(container), '/apartment');
  });

  testWidgets('a locked scene is not played: out to `then`', (tester) async {
    // `the_stand` waits for «المعلم»'s trip.
    final container = await _open(tester, '/story/scene/the_stand?then=/home');
    expect(locationOf(container), '/home');
    // The launch's backfill may have recorded the opening M07 saw; the
    // locked scene itself is never recorded.
    expect(_seen(container, 'ch1_first_job'), isNot(contains('the_stand')));
  });

  testWidgets('a chapter with nothing unlocked goes out', (tester) async {
    final container = await _open(tester, '/story/ch2_her_father');
    expect(locationOf(container), '/apartment');
  });

  testWidgets('`then` is only a place the app knows', (tester) async {
    final container = await _open(
      tester,
      '/story/scene/opening?then=/settings/account',
    );
    await tester.tap(find.byKey(SceneViewerPage.skipKey));
    await tester.pumpAndSettle();
    expect(locationOf(container), '/home');
  });

  testWidgets('reduced motion: every bubble at once, no waiting', (
    tester,
  ) async {
    await _open(tester, '/story/scene/opening', reduced: true, settle: false);
    await tester.pump(const Duration(milliseconds: 150));
    await _next(tester);
    expect(find.byKey(ScenePanelView.bubbleKey(0)), findsOneWidget);
    expect(find.byKey(ScenePanelView.bubbleKey(1)), findsOneWidget);
    // Both are already visible: no Opacity(0) holds either back.
    for (final i in [0, 1]) {
      final hidden = find.ancestor(
        of: find.byKey(ScenePanelView.bubbleKey(i)),
        matching: find.byWidgetPredicate((w) => w is Opacity && w.opacity == 0),
      );
      expect(hidden, findsNothing);
    }
    // A panel change is a crossfade within 150 ms.
    await tester.tap(find.byKey(SceneViewerPage.panelKey));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();
    expect(_activeDot(tester, 3), 2);
    expect(find.byType(SlideTransition), findsNothing);
  });

  testWidgets('each advance is announced as «اللوحة {i} من {n}»', (
    tester,
  ) async {
    final announced = <String>[];
    tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(
      SystemChannels.accessibility,
      (message) async {
        if (message is Map && message['type'] == 'announce') {
          final data = message['data'];
          if (data is Map) announced.add(data['message'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger
          .setMockDecodedMessageHandler<dynamic>(
            SystemChannels.accessibility,
            null,
          ),
    );
    await _open(tester, '/story/scene/opening');
    await _next(tester);
    final total = _scene('opening').panels.length;
    const numbers = NumberFormatter(DigitStyle.arabicIndic);
    expect(announced, [
      _l10n.introPageOf(numbers.integer(2), numbers.integer(total)),
    ]);
  });

  testWidgets('the panel is one button: «اللوحة الجاية», its bubbles read in '
      'order', (tester) async {
    final semantics = tester.ensureSemantics();
    await _open(tester, '/story/scene/opening');
    await _next(tester);
    expect(
      find.bySemanticsLabel(_l10n.sceneViewerNextPanelA11y),
      findsOneWidget,
    );
    final speakerA = tester.getSemantics(
      find.byKey(ScenePanelView.bubbleKey(0)),
    );
    final speakerB = tester.getSemantics(
      find.byKey(ScenePanelView.bubbleKey(1)),
    );
    expect(speakerA.label, contains(_l10n.sceneSpeaker('moallem')));
    expect(speakerB.label, contains('أحمد'));
    semantics.dispose();
  });
}
