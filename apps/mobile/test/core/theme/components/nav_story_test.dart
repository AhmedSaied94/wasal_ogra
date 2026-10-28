import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/core/theme/components/app_icon.dart';
import 'package:wassal/core/theme/components/bubble_pop.dart';
import 'package:wassal/core/theme/components/nav.dart';
import 'package:wassal/core/theme/components/pills.dart';
import 'package:wassal/core/theme/components/pressable.dart';
import 'package:wassal/core/theme/components/story.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';

import '../../../helpers/design_component.dart';

// The bottom nav, the daily circles, and the story pieces (HANDOFF §3.3).

Finder _inCell(int i, Finder matching) =>
    find.descendant(of: find.byKey(BottomNav.cellKey(i)), matching: matching);

Future<void> _pumpNav(
  WidgetTester tester, {
  int current = 0,
  List<bool> newDots = const [false, false, false, false],
  List<bool> disabled = const [false, false, false, false],
  ValueChanged<int>? onTap,
}) => pumpDesignComponent(
  tester,
  SizedBox(
    width: 390,
    child: BottomNav(
      currentIndex: current,
      onTap: onTap ?? (_) {},
      newDots: newDots,
      disabled: disabled,
    ),
  ),
);

void main() {
  group('BottomNav', () {
    testWidgets('four equal tabs, 88 high, labels 13 pt', (tester) async {
      await _pumpNav(tester);
      expect(tester.getSize(find.byType(BottomNav)).height, 88);
      final widths = [
        for (var i = 0; i < 4; i++)
          tester.getSize(find.byKey(BottomNav.cellKey(i))).width,
      ];
      expect(widths.toSet(), hasLength(1));
      for (final label in ['الموقف', 'الخطوط', 'الشقة', 'المحل']) {
        expect(tester.widget<Text>(find.text(label)).style!.fontSize, 13);
      }
    });

    testWidgets('a disabled tab: at 0.45, no tap, «المحل، محتاج نت»', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final taps = <int>[];
      await _pumpNav(
        tester,
        disabled: const [false, false, false, true],
        onTap: taps.add,
      );
      final dimmed = tester.widget<Opacity>(
        find
            .ancestor(
              of: _inCell(3, find.byType(AppIcon)),
              matching: find.byType(Opacity),
            )
            .first,
      );
      expect(dimmed.opacity, Pressable.disabledOpacity);
      await tester.tap(find.byKey(BottomNav.cellKey(3)));
      await tester.tap(find.byKey(BottomNav.cellKey(1)));
      expect(taps, [1]);
      expect(
        tester.getSemantics(find.byKey(BottomNav.cellKey(3))),
        isSemantics(
          label: 'المحل، محتاج نت',
          hasEnabledState: true,
          isEnabled: false,
        ),
      );
      semantics.dispose();
    });

    testWidgets('RTL: الموقف is the right-most tab', (tester) async {
      await _pumpNav(tester);
      final home = tester.getCenter(find.byKey(BottomNav.cellKey(0))).dx;
      final shop = tester.getCenter(find.byKey(BottomNav.cellKey(3))).dx;
      expect(home, greaterThan(shop));
    });

    testWidgets('the active tab: a 60×34 primary pill, a white glyph', (
      tester,
    ) async {
      await _pumpNav(tester, current: 1);
      final pill = _inCell(1, find.byKey(BottomNav.pillKey));
      expect(tester.getSize(pill), const Size(60, 34));
      final opacity = tester.widget<AnimatedOpacity>(
        find.ancestor(of: pill, matching: find.byType(AnimatedOpacity)).first,
      );
      expect(opacity.opacity, 1);
      final icon = tester.widget<AppIcon>(_inCell(1, find.byType(AppIcon)));
      expect(icon.name, 'nav_lines');
      expect(icon.color, ColorTokens.paper);
      final label = tester.widget<Text>(_inCell(1, find.byType(Text)));
      expect(label.style!.color, ColorTokens.primary);
      expect(label.style!.fontWeight, FontWeight.w700);
    });

    testWidgets('an inactive tab: no pill, an icon.off glyph, ink.muted', (
      tester,
    ) async {
      await _pumpNav(tester, current: 1);
      final opacity = tester.widget<AnimatedOpacity>(
        find
            .ancestor(
              of: _inCell(0, find.byKey(BottomNav.pillKey)),
              matching: find.byType(AnimatedOpacity),
            )
            .first,
      );
      expect(opacity.opacity, 0);
      final icon = tester.widget<AppIcon>(_inCell(0, find.byType(AppIcon)));
      expect(icon.name, 'nav_home');
      expect(icon.color, ColorTokens.iconOff);
      final label = tester.widget<Text>(_inCell(0, find.byType(Text)));
      expect(label.style!.color, ColorTokens.inkMuted);
    });

    testWidgets('home and apartment have their own active glyphs', (
      tester,
    ) async {
      await _pumpNav(tester, current: 2);
      expect(
        tester.widget<AppIcon>(_inCell(2, find.byType(AppIcon))).name,
        'nav_apartment_active',
      );
    });

    testWidgets("the new-dot sits on the icon's top-end corner", (
      tester,
    ) async {
      await _pumpNav(tester, newDots: const [false, false, true, false]);
      expect(find.byType(NewDot), findsOne);
      expect(_inCell(2, find.byType(NewDot)), findsOne);
      final dot = tester.getRect(find.byType(NewDot));
      final icon = tester.getRect(_inCell(2, find.byType(AppIcon)));
      // `Components` boxes 182–183: 7.5 above the icon, poking 10.8 out of
      // its end (left) side.
      expect(dot.top, closeTo(icon.top - 7.5, 0.5));
      expect(dot.left, closeTo(icon.left - 10.8, 0.5));
      expect(
        tester.getSemantics(find.byKey(BottomNav.cellKey(2))).label,
        contains('جديد'),
      );
    });

    testWidgets('a tap on a tab reports its index', (tester) async {
      final tapped = <int>[];
      await _pumpNav(tester, onTap: tapped.add);
      await tester.tap(find.byKey(BottomNav.cellKey(3)));
      await tester.tap(find.byKey(BottomNav.cellKey(1)));
      expect(tapped, [3, 1]);
    });

    testWidgets('the bottom inset goes under the tabs', (tester) async {
      tester.view.viewPadding = const FakeViewPadding(bottom: 24);
      addTearDown(tester.view.resetViewPadding);
      await _pumpNav(tester);
      expect(tester.getSize(find.byType(BottomNav)).height, 88 + 24);
    });
  });

  group('DailyCircle', () {
    testWidgets('normal: a 46 white circle in a 58×65 tap, the label chip', (
      tester,
    ) async {
      var taps = 0;
      await pumpDesignComponent(
        tester,
        DailyCircle(icon: 'gift', label: 'الهدية', onTap: () => taps++),
      );
      expect(tester.getSize(find.byType(DailyCircle)), DailyCircle.tapArea);
      final circle = tester.widget<Container>(
        find.byKey(DailyCircle.circleKey),
      );
      final d = circle.decoration! as BoxDecoration;
      expect(d.color, ColorTokens.paper);
      expect(d.boxShadow, [LipTokens.bubble]);
      expect(tester.getSize(find.byKey(DailyCircle.circleKey)).width, 46);
      expect(find.text('الهدية'), findsOne);
      await tester.tap(find.byType(DailyCircle));
      expect(taps, 1);
    });

    testWidgets('event: filled with the first station colour', (tester) async {
      await pumpDesignComponent(
        tester,
        DailyCircle(icon: 'gift', label: 'رمضان', event: true, onTap: () {}),
      );
      final circle = tester.widget<Container>(
        find.byKey(DailyCircle.circleKey),
      );
      expect(
        (circle.decoration! as BoxDecoration).color,
        StationColors.all.first.bg,
      );
    });

    testWidgets('a new-dot, or a count badge', (tester) async {
      await pumpDesignComponent(
        tester,
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            DailyCircle(
              icon: 'gift',
              label: 'الهدية',
              isNew: true,
              onTap: () {},
            ),
            DailyCircle(
              icon: 'tasks',
              label: 'المهام',
              count: '٢/٣',
              onTap: () {},
            ),
          ],
        ),
      );
      expect(find.byType(NewDot), findsOne);
      expect(find.widgetWithText(CountBadge, '٢/٣'), findsOne);
    });
  });

  testWidgets('ComicPanel: the art, the caption, the speaker and the line', (
    tester,
  ) async {
    await pumpDesignComponent(
      tester,
      const SizedBox(
        width: 358,
        height: 540,
        child: ComicPanel(
          art: ColoredBox(key: Key('art'), color: ColorTokens.sceneSky),
          caption: 'الموقف، الصبح بدري',
          lines: [('المعلم', 'خد مفتاح التوكتوك.')],
        ),
      ),
    );
    expect(find.byKey(const Key('art')), findsOne);
    expect(find.text('الموقف، الصبح بدري'), findsOne);
    expect(find.text('المعلم'), findsOne);
    expect(find.text('خد مفتاح التوكتوك.'), findsOne);
    // The caption sits at the top-end (left) corner, the line at the start.
    final panel = tester.getRect(find.byType(ComicPanel));
    expect(
      tester.getRect(find.text('الموقف، الصبح بدري')).center.dx,
      lessThan(panel.center.dx),
    );
    expect(
      tester.getRect(find.text('المعلم')).right,
      greaterThan(panel.center.dx),
    );
    // `Intro` box 6: the bubble 236 wide, 76 below the panel's top.
    final bubble = tester.getRect(find.byKey(ComicPanel.bubbleKey(0)));
    expect(bubble.width, 236);
    expect(bubble.top - panel.top, 76);
  });

  group('ComicPanel with two lines (M07 contracts/scenes.md)', () {
    Future<void> pumpTwo(WidgetTester tester, {String? caption}) =>
        pumpDesignComponent(
          tester,
          SizedBox(
            width: 358,
            height: 540,
            child: ComicPanel(
              art: const SizedBox.shrink(),
              caption: caption,
              lines: const [
                ('المعلم', 'الركاب بيدفعوا.'),
                ('الأسطى', 'وأنا أرجّع الباقي.'),
              ],
            ),
          ),
        );

    testWidgets('two bubbles, the second under the first', (tester) async {
      await pumpTwo(tester);
      final first = tester.getRect(find.byKey(ComicPanel.bubbleKey(0)));
      final second = tester.getRect(find.byKey(ComicPanel.bubbleKey(1)));
      expect(second.top, greaterThan(first.bottom));
      expect(find.text('المعلم'), findsOne);
      expect(find.text('وأنا أرجّع الباقي.'), findsOne);
    });

    testWidgets('the caption chip comes from the caption only', (tester) async {
      await pumpTwo(tester);
      expect(find.byKey(ComicPanel.captionKey), findsNothing);
      await pumpTwo(tester, caption: 'الموقف');
      expect(
        find.descendant(
          of: find.byKey(ComicPanel.captionKey),
          matching: find.text('الموقف'),
        ),
        findsOne,
      );
    });

    testWidgets('no lines, no bubble', (tester) async {
      await pumpDesignComponent(
        tester,
        const SizedBox(
          width: 358,
          height: 540,
          child: ComicPanel(art: SizedBox.shrink(), caption: 'الموقف'),
        ),
      );
      expect(find.byKey(ComicPanel.bubbleKey(0)), findsNothing);
    });
  });

  // Bubbles in turn (specs/012.5-m22-animated-scenes,
  // contracts/scene-turns.md "Bubbles").
  group('ComicPanel in turns', () {
    const two = [
      ('المعلم', 'الركاب بيدفعوا.'),
      ('الأسطى', 'وأنا أرجّع الباقي.'),
    ];

    Future<void> pumpShown(
      WidgetTester tester,
      int? shown, {
      List<(String, String)> lines = two,
      bool reducedMotion = false,
    }) => pumpDesignComponent(
      tester,
      SizedBox(
        width: 358,
        height: 540,
        child: ComicPanel(
          art: const SizedBox.shrink(),
          lines: lines,
          shown: shown,
        ),
      ),
      reducedMotion: reducedMotion,
    );

    Finder popOf(int i) => find.ancestor(
      of: find.byKey(ComicPanel.bubbleKey(i)),
      matching: find.byType(BubblePop),
    );

    double scaleOf(WidgetTester tester, int i) => tester
        .widget<Transform>(
          find.descendant(of: popOf(i), matching: find.byType(Transform)).first,
        )
        .transform
        .entry(0, 0);

    testWidgets("shown null is M07's panel: every bubble, no pop", (
      tester,
    ) async {
      await pumpShown(tester, null);
      for (final i in [0, 1]) {
        expect(find.byKey(ComicPanel.bubbleKey(i)), findsOne);
        expect(popOf(i), findsNothing);
      }
    });

    testWidgets('a bubble not shown yet keeps its place and its line, '
        'unseen and untouchable', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpShown(tester, 2);
      await tester.pumpAndSettle();
      final place = tester.getRect(find.byKey(ComicPanel.bubbleKey(1)));
      await pumpShown(tester, 1);
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byKey(ComicPanel.bubbleKey(1))), place);
      final opacity = tester.widget<Opacity>(
        find.ancestor(
          of: find.byKey(ComicPanel.bubbleKey(1)),
          matching: find.byType(Opacity),
        ),
      );
      expect(opacity.opacity, 0);
      expect(opacity.alwaysIncludeSemantics, isTrue);
      expect(
        tester
            .widget<IgnorePointer>(
              find
                  .ancestor(
                    of: find.byKey(ComicPanel.bubbleKey(1)),
                    matching: find.byType(IgnorePointer),
                  )
                  .first,
            )
            .ignoring,
        isTrue,
      );
      expect(
        find.bySemanticsLabel(RegExp('وأنا أرجّع الباقي')),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('a bubble pops when it is shown', (tester) async {
      await pumpShown(tester, 1);
      await tester.pumpAndSettle();
      await pumpShown(tester, 2);
      await tester.pump(const Duration(milliseconds: 16));
      expect(scaleOf(tester, 1), lessThan(1));
      // The one already shown doesn't pop again.
      expect(scaleOf(tester, 0), 1);
      await tester.pump(MotionTokens.bubblePop);
      expect(scaleOf(tester, 1), 1);
    });

    testWidgets('under reduced motion it appears at once', (tester) async {
      await pumpShown(tester, 1, reducedMotion: true);
      await pumpShown(tester, 2, reducedMotion: true);
      expect(popOf(1), findsOne);
      expect(
        find.descendant(
          of: popOf(1),
          matching: find.byType(TweenAnimationBuilder<double>),
        ),
        findsNothing,
        reason: 'no grow from 0.6',
      );
    });

    const three = [...two, ('المعلم', 'يلا.')];

    /// The `Opacity` [i]'s turn wraps it in, if any.
    Opacity? hiding(WidgetTester tester, int i) {
      final found = find.ancestor(
        of: find.byKey(ComicPanel.bubbleKey(i)),
        matching: find.byType(Opacity),
      );
      return found.evaluate().isEmpty ? null : tester.widget<Opacity>(found);
    }

    testWidgets('at most two bubbles show, the last two; the oldest keeps '
        'its place, unseen and still read (FR-018)', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpShown(tester, 2, lines: three);
      await tester.pumpAndSettle();
      final place = tester.getRect(find.byKey(ComicPanel.bubbleKey(0)));
      await pumpShown(tester, 3, lines: three);
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byKey(ComicPanel.bubbleKey(0))), place);
      expect(hiding(tester, 0)?.opacity, 0);
      expect(hiding(tester, 0)?.alwaysIncludeSemantics, isTrue);
      expect(find.bySemanticsLabel(RegExp('الركاب بيدفعوا')), findsOneWidget);
      for (final i in [1, 2]) {
        expect(popOf(i), findsOne, reason: 'bubble $i');
        expect(hiding(tester, i), isNull, reason: 'bubble $i');
      }
      semantics.dispose();
    });

    testWidgets("shown null with three lines is M07's: every bubble shows "
        '(FR-017)', (tester) async {
      await pumpShown(tester, null, lines: three);
      for (final i in [0, 1, 2]) {
        expect(find.byKey(ComicPanel.bubbleKey(i)), findsOne);
        expect(hiding(tester, i), isNull, reason: 'bubble $i');
      }
    });
  });

  group('PageDots (Intro boxes 10–13)', () {
    for (final digits in [DigitStyle.arabicIndic, DigitStyle.western]) {
      testWidgets('3 dots, the first active, in ${digits.name} digits', (
        tester,
      ) async {
        await pumpDesignComponent(
          tester,
          SizedBox(
            width: 358,
            child: PageDots(
              count: 3,
              index: 0,
              label: digits == DigitStyle.western
                  ? 'اللوحة 1 من 3'
                  : 'اللوحة ١ من ٣',
            ),
          ),
        );
        final dots = [
          for (var i = 0; i < 3; i++)
            tester.getRect(find.byKey(PageDots.dotKey(i))),
        ];
        expect(dots[0].size, const Size(26, 10));
        expect(dots[1].size, const Size(10, 10));
        expect(dots[2].size, const Size(10, 10));
        // RTL: the first panel's dot is on the right, 8 apart.
        expect(dots[0].left - dots[1].right, 8);
        expect(dots[1].left - dots[2].right, 8);
        expect(
          find.bySemanticsLabel(
            digits == DigitStyle.western ? 'اللوحة 1 من 3' : 'اللوحة ١ من ٣',
          ),
          findsOne,
        );
      });
    }

    testWidgets('the active pill moves with the index, in colour', (
      tester,
    ) async {
      await pumpDesignComponent(
        tester,
        const SizedBox(
          width: 358,
          child: PageDots(count: 3, index: 2, label: 'اللوحة ٣ من ٣'),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byKey(PageDots.dotKey(2))).width, 26);
      expect(tester.getSize(find.byKey(PageDots.dotKey(0))).width, 10);
      final dots = tester.getRect(find.byType(PageDots));
      expect(
        tester.getRect(find.byKey(PageDots.dotKey(2))).left,
        closeTo(dots.center.dx - 31, 0.5),
      );
    });
  });

  group('CoachMark', () {
    const target = Rect.fromLTWH(198, 648, 87, 44);

    Future<(List<String>,)> pumpCoach(WidgetTester tester) async {
      final taps = <String>[];
      await pumpDesignComponent(
        tester,
        SizedBox(
          width: 390,
          height: 844,
          child: Stack(
            children: [
              Positioned.fromRect(
                rect: target,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => taps.add('target'),
                ),
              ),
              Positioned(
                left: 12,
                top: 648,
                width: 87,
                height: 44,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => taps.add('other'),
                ),
              ),
              const Positioned.fill(child: CoachMark(target: target)),
            ],
          ),
        ),
      );
      return (taps,);
    }

    testWidgets('only the target inside the hole takes a tap', (tester) async {
      final (taps,) = await pumpCoach(tester);
      await tester.tapAt(target.center);
      await tester.tapAt(const Offset(55, 670));
      await tester.tapAt(const Offset(195, 300));
      await tester.pump();
      expect(taps, ['target']);
    });

    testWidgets('the hole: the target and 6 around it, radius 18', (
      tester,
    ) async {
      await pumpCoach(tester);
      final mark = tester.widget<CoachMark>(find.byType(CoachMark));
      expect(mark.hole, const Rect.fromLTWH(192, 642, 99, 56));
      expect(CoachMark.holeRadius, 18);
      expect(CoachMark.ringWidth, 4);
    });

    testWidgets('reduced motion: the hand holds still', (tester) async {
      await pumpDesignComponent(
        tester,
        const SizedBox(
          width: 390,
          height: 844,
          child: CoachMark(target: target),
        ),
        reducedMotion: true,
      );
      await tester.pump();
      expect(tester.hasRunningAnimations, isFalse);
    });
  });

  group('MicrobusLoader', () {
    testWidgets('a 200×16 road, a 36×24 marker that drives, the label', (
      tester,
    ) async {
      await pumpDesignComponent(
        tester,
        const MicrobusLoader(label: 'بنحمّل الخط..'),
      );
      expect(
        tester.getSize(find.byKey(MicrobusLoader.roadKey)),
        MicrobusLoader.road,
      );
      expect(
        tester.getSize(find.byKey(MicrobusLoader.markerKey)),
        MicrobusLoader.marker,
      );
      expect(find.text('بنحمّل الخط..'), findsOne);
      final before = tester.getRect(find.byKey(MicrobusLoader.markerKey));
      await tester.pump(const Duration(milliseconds: 300));
      final after = tester.getRect(find.byKey(MicrobusLoader.markerKey));
      // RTL: it drives from right to left.
      expect(after.left, lessThan(before.left));
    });

    testWidgets('reduced motion: the marker stands still', (tester) async {
      await pumpDesignComponent(
        tester,
        const MicrobusLoader(label: 'بنحمّل الخط..'),
        reducedMotion: true,
      );
      await tester.pump();
      expect(tester.hasRunningAnimations, isFalse);
    });
  });
}
