import 'package:content_models/content_models.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/art/panel_art.dart';
import 'package:wassal/core/art/rive_scenes.dart';
import 'package:wassal/core/audio_haptics/audio_haptics_providers.dart';
import 'package:wassal/core/theme/components/story.dart';
import 'package:wassal/features/onboarding/domain/first_session.dart';
import 'package:wassal/features/onboarding/presentation/scene_player.dart';

import '../../../helpers/design_component.dart';
import '../../../helpers/economy.dart';
import '../../../helpers/routing.dart';
import '../../../helpers/trip.dart';
import '../../../helpers/tutorial_content.dart';

// An animated panel's lines in turn (specs/012.5-m22-animated-scenes,
// contracts/scene-turns.md): each speaker's bubble appears and they talk
// for their turn, «يلا» first shows the rest, then moves on. Without Rive's
// library: `scenePanelsProvider` says which panels animate, and the art
// itself falls back to its drawing.

Scene get _opening => sceneOf(sampleContent(), 'opening')!;

Duration _ms(int n) => Duration(milliseconds: n);

/// Every panel animates.
const _every = ScenePanels({...scenePanelSlugs});

/// The time since the panel on screen showed.
class _Clock {
  _Clock(this.tester);

  final WidgetTester tester;
  var _now = Duration.zero;

  Future<void> to(int ms) async {
    final t = _ms(ms);
    expect(t, greaterThanOrEqualTo(_now), reason: 'the clock goes forward');
    await tester.pump(t - _now);
    _now = t;
  }

  /// «يلا», then the frame that shows its result; a new panel starts its
  /// clock there.
  Future<void> next() async {
    await tester.tap(find.byKey(ScenePlayer.nextKey));
    await tester.pump();
    _now = Duration.zero;
  }
}

/// [panels] null keeps the real `scenePanelsProvider`, over no file.
Future<List<void>> _pump(
  WidgetTester tester, {
  Scene? scene,
  ScenePanels? panels = _every,
  bool reducedMotion = false,
  FakeHaptics? haptics,
  FakeSfxPlayer? sfx,
}) async {
  final finished = <void>[];
  await pumpDesignComponent(
    tester,
    ScenePlayer(
      title: 'أول شغلانة',
      scene: scene ?? _opening,
      driverName: 'الأسطى',
      onFinished: () => finished.add(null),
    ),
    center: false,
    haptics: haptics,
    reducedMotion: reducedMotion,
    overrides: [
      if (panels != null) scenePanelsProvider.overrideWithValue(panels),
      if (sfx != null) sfxPlayerProvider.overrideWithValue(sfx),
    ],
  );
  return finished;
}

/// The panel on screen (the outgoing one comes first while they swap).
ComicPanel _comic(WidgetTester tester) =>
    tester.widget<ComicPanel>(find.byType(ComicPanel).last);

PanelArt _art(WidgetTester tester) =>
    tester.widget<PanelArt>(find.byType(PanelArt).last);

int _dotIndex(WidgetTester tester) =>
    tester.widget<PageDots>(find.byType(PageDots)).index;

/// Turns the platform's reduce-motion setting [on] or off mid-scene.
Future<void> _reduceMotion(WidgetTester tester, {required bool on}) async {
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      FakeAccessibilityFeatures(disableAnimations: on);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  await tester.pump();
}

/// The panel on screen is M07's: every bubble, nobody talks.
void _expectStill(WidgetTester tester, {required bool animate}) {
  expect(_allShown(tester), isTrue);
  expect(_art(tester).talking, isNull);
  expect(_art(tester).animate, animate);
}

/// Whether every bubble of the panel on screen can be seen.
bool _allShown(WidgetTester tester) {
  final panel = _comic(tester);
  return panel.shown == null || panel.shown! >= panel.lines.length;
}

/// Every label in the semantics tree under [node], in traversal order.
List<String> _readOrder(SemanticsNode node) {
  final labels = <String>[];
  void visit(SemanticsNode n) {
    final label = n.label.replaceAll(RegExp('[\u2066-\u2069]'), '').trim();
    if (label.isNotEmpty) labels.add(label);
    for (final child in n.debugListChildrenInOrder(
      DebugSemanticsDumpOrder.traversalOrder,
    )) {
      visit(child);
    }
  }

  visit(node);
  return labels;
}

/// The opening's turns (research R5): each panel's speakers, from and to,
/// in ms since the panel showed.
const _openingTurns = [
  [('moallem', 280, 2980)],
  [('moallem', 280, 2380), ('usta', 2680, 4000)],
  [('belya', 280, 1780), ('moallem', 2080, 3280)],
];

/// Checks [turns] on the panel on screen: at each turn's start, middle and
/// 1 ms before its end the speaker talks, with their bubble the newest
/// shown; at its end nobody does.
Future<void> _expectTurns(
  WidgetTester tester,
  _Clock clock,
  List<(String, int, int)> turns,
) async {
  for (final (i, (speaker, from, to)) in turns.indexed) {
    for (final t in [from, (from + to) ~/ 2, to - 1]) {
      await clock.to(t);
      expect(_art(tester).talking, speaker, reason: '$speaker at $t ms');
      expect(_comic(tester).shown, i + 1, reason: 'bubbles at $t ms');
    }
    await clock.to(to);
    expect(_art(tester).talking, isNull, reason: 'after $speaker, at $to ms');
  }
}

/// Plays the scene on screen panel by panel, checking each panel's [table]
/// row.
Future<void> _expectScene(
  WidgetTester tester,
  List<List<(String, int, int)>> table,
) async {
  final clock = _Clock(tester);
  for (final (i, turns) in table.indexed) {
    expect(_dotIndex(tester), i);
    expect(_art(tester).animate, isTrue, reason: 'panel ${i + 1}');
    await _expectTurns(tester, clock, turns);
    if (i + 1 < table.length) await clock.next();
  }
}

/// The سلمى scene's three animations, under the sample's names.
const _salmaPanels = ScenePanels({
  'stand_morning',
  'salma_waiting',
  'usta_decides',
});

void main() {
  testWidgets('every spoken line of the opening talks for exactly its turn', (
    tester,
  ) async {
    await _pump(tester);
    await _expectScene(tester, _openingTurns);
  });

  testWidgets("every spoken line of the sample's the_stand talks for its "
      'turn', (tester) async {
    await _pump(
      tester,
      scene: sceneOf(sampleContent(), 'the_stand'),
      panels: _salmaPanels,
    );
    await _expectScene(tester, [
      [('usta', 280, 1480)],
      [('salma', 280, 1840)],
      [('usta', 280, 1780)],
    ]);
  });

  testWidgets("the draft's first_sight, under its ch1_ names, animates "
      'through the aliases, every line in its turn', (tester) async {
    await _pump(tester, scene: draftFirstSight(), panels: _salmaPanels);
    await _expectScene(tester, [
      [('usta', 280, 1840)],
      [('salma', 280, 2080), ('usta', 2380, 3580)],
      // The usta twice, nobody talking in the pause.
      [('usta', 280, 1660), ('usta', 1960, 3340)],
    ]);
  });

  testWidgets('opening_stand, step by step: one bubble, the pause, the '
      'second, then both stay', (tester) async {
    await _pump(tester);
    final clock = _Clock(tester);
    await clock.to(300);
    await clock.next();
    expect(_dotIndex(tester), 1);
    expect(_comic(tester).shown, 0);
    expect(_art(tester).talking, isNull);

    await clock.to(280);
    expect(_comic(tester).shown, 1);
    expect(_art(tester).talking, 'moallem');
    await clock.to(2380);
    expect(_comic(tester).shown, 1);
    expect(_art(tester).talking, isNull, reason: 'the pause');
    await clock.to(2680);
    expect(_comic(tester).shown, 2);
    expect(_art(tester).talking, 'usta');
    await clock.to(4000);
    expect(_allShown(tester), isTrue);
    expect(_art(tester).talking, isNull);
    await clock.to(14000);
    expect(_dotIndex(tester), 1, reason: 'the panel never moves on alone');
    expect(_art(tester).animate, isTrue);
    // Past the clock's end, it stays the panel's end, not its start.
    expect(_allShown(tester), isTrue);
    expect(_art(tester).talking, isNull);
  });

  testWidgets('once every turn has ended, one «يلا» moves on, on every '
      'panel', (tester) async {
    final finished = await _pump(tester);
    final clock = _Clock(tester);
    for (var i = 0; i < 3; i++) {
      // Past each panel's last turn: 2980, 4000 and 3280 ms.
      await clock.to(4500);
      expect(_allShown(tester), isTrue, reason: 'panel ${i + 1}');
      await clock.next();
      if (i < 2) expect(_dotIndex(tester), i + 1, reason: 'one tap');
    }
    expect(finished, hasLength(1));
  });

  testWidgets('inside a turn the player doesn\'t rebuild', (tester) async {
    await _pump(tester);
    final clock = _Clock(tester);
    await clock.to(500);
    final before = _comic(tester);
    for (var i = 0; i < 10; i++) {
      await tester.pump(_ms(16));
    }
    expect(identical(_comic(tester), before), isTrue);
    expect(_art(tester).talking, 'moallem');
  });

  testWidgets('«يلا» before the last turn shows every bubble and stays; the '
      'next moves on', (tester) async {
    await _pump(tester);
    final clock = _Clock(tester);
    await clock.to(300);
    await clock.next();
    await clock.to(500);
    expect(_allShown(tester), isFalse);
    await clock.next();
    expect(_dotIndex(tester), 1);
    expect(_allShown(tester), isTrue);
    expect(_art(tester).talking, isNull);
    expect(_art(tester).animate, isTrue);
    await clock.to(5000);
    expect(_art(tester).talking, isNull, reason: 'no turn starts again');
    expect(_dotIndex(tester), 1);
    await clock.next();
    expect(_dotIndex(tester), 2);
  });

  testWidgets('«يلا» once the last turn has started moves on at once', (
    tester,
  ) async {
    await _pump(tester);
    final clock = _Clock(tester);
    await clock.to(300);
    await clock.next();
    await clock.to(2800);
    expect(_art(tester).talking, 'usta');
    await clock.next();
    expect(_dotIndex(tester), 2);
  });

  testWidgets('«تخطّى» during a turn finishes once', (tester) async {
    final finished = await _pump(tester);
    final clock = _Clock(tester);
    await clock.to(500);
    await tester.tap(find.byKey(ScenePlayer.skipKey));
    await tester.pump();
    expect(finished, hasLength(1));
    await tester.tap(find.byKey(ScenePlayer.skipKey));
    await tester.tap(find.byKey(ScenePlayer.nextKey));
    await tester.pumpAndSettle();
    expect(finished, hasLength(1));
  });

  testWidgets('back during a turn finishes once', (tester) async {
    final finished = await _pump(tester);
    await _Clock(tester).to(500);
    await pressBack(tester);
    expect(finished, hasLength(1));
  });

  testWidgets('the caption shows with the panel and takes no turn', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.byKey(ComicPanel.captionKey), findsOneWidget);
    expect(_comic(tester).caption, 'الموقف، الصبح بدري');
    expect(_comic(tester).shown, 0);
    expect(_art(tester).talking, isNull);
  });

  testWidgets('a caption-only panel moves on at the first «يلا»', (
    tester,
  ) async {
    const scene = Scene(
      sceneId: 'test',
      title: LocalizedText(arEg: 'مشهد'),
      panels: [
        Panel(
          art: 'opening_key',
          lines: [
            PanelLine(
              speaker: 'narrator',
              text: LocalizedText(arEg: 'الموقف'),
            ),
          ],
        ),
        Panel(art: 'opening_go', lines: []),
      ],
    );
    await _pump(tester, scene: scene);
    expect(_allShown(tester), isTrue);
    await _Clock(tester).next();
    expect(_dotIndex(tester), 1);
  });

  testWidgets('every line is in the read order from the panel\'s start', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester);
    expect(_comic(tester).shown, 0);
    final order = _readOrder(tester.getSemantics(find.byType(ScenePlayer)));
    final wanted = [
      'أول شغلانة',
      'الموقف، الصبح بدري',
      'المعلم',
      'اللوحة ١ من ٣',
      'يلا',
      'تخطّى',
    ];
    final positions = [
      for (final label in wanted) order.indexWhere((l) => l.contains(label)),
    ];
    expect(positions, everyElement(greaterThanOrEqualTo(0)), reason: '$order');
    expect(positions, [...positions]..sort(), reason: 'read order $order');
    expect(order[positions[2]], contains('خد مفتاح التوكتوك'));
    semantics.dispose();
  });

  testWidgets('no sound over the scene, and one press tick per tap', (
    tester,
  ) async {
    final haptics = FakeHaptics();
    final sfx = FakeSfxPlayer();
    final finished = await _pump(tester, haptics: haptics, sfx: sfx);
    final clock = _Clock(tester);
    await clock.to(100);
    await clock.next(); // the reveal
    await clock.next(); // the next panel
    await clock.to(3000);
    await clock.next(); // its last turn has started: the last panel
    await clock.next(); // the reveal, before its first turn
    await clock.to(4000);
    await tester.tap(find.byKey(ScenePlayer.skipKey));
    await tester.pump();
    expect(finished, hasLength(1));
    expect(haptics.felt, List.filled(5, 'selection'));
    expect(sfx.played, isEmpty);
  });

  // When a panel doesn't animate, it is M07's (spec US2, contracts/scene-
  // turns.md "When a panel has turns").
  group('still panels', () {
    testWidgets('without the file: every panel is M07\'s, and «يلا» moves '
        'on', (tester) async {
      final finished = await _pump(tester, panels: null);
      final clock = _Clock(tester);
      for (var i = 0; i < 3; i++) {
        await clock.to(500);
        expect(_dotIndex(tester), i);
        _expectStill(tester, animate: false);
        await clock.next();
      }
      expect(finished, hasLength(1));
    });

    testWidgets('with only opening_stand animating, panels 1 and 3 are '
        'M07\'s', (tester) async {
      await _pump(tester, panels: const ScenePanels({'opening_stand'}));
      final clock = _Clock(tester);
      await clock.to(500);
      _expectStill(tester, animate: false);
      await clock.next();
      await clock.to(500);
      expect(_art(tester).animate, isTrue);
      expect(_art(tester).talking, 'moallem');
      expect(_allShown(tester), isFalse);
      await clock.to(2800);
      await clock.next();
      await clock.to(500);
      expect(_dotIndex(tester), 2);
      _expectStill(tester, animate: false);
    });

    testWidgets('under reduced motion: every bubble at once, nobody talks', (
      tester,
    ) async {
      await _pump(tester, reducedMotion: true);
      final clock = _Clock(tester);
      for (var i = 0; i < 3; i++) {
        await clock.to(500);
        _expectStill(tester, animate: false);
        await clock.next();
      }
    });

    testWidgets('reduced motion turned on mid-turn: every bubble, nobody '
        'talks', (tester) async {
      await _pump(tester);
      final clock = _Clock(tester);
      await clock.to(300);
      await clock.next();
      await clock.to(500);
      expect(_art(tester).talking, 'moallem');
      await _reduceMotion(tester, on: true);
      _expectStill(tester, animate: false);
      await clock.to(3000);
      _expectStill(tester, animate: false);
    });

    testWidgets('reduced motion turned off on a panel that showed still: it '
        'animates, with no turn', (tester) async {
      await _pump(tester, reducedMotion: true);
      final clock = _Clock(tester);
      await clock.to(500);
      await _reduceMotion(tester, on: false);
      _expectStill(tester, animate: true);
      await clock.to(3000);
      _expectStill(tester, animate: true);
      await clock.next();
      expect(_dotIndex(tester), 1, reason: 'no turn to reveal first');
    });
  });
}
