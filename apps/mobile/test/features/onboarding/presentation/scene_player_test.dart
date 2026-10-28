import 'package:content_models/content_models.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/routing/router.dart';
import 'package:wassal/core/theme/components/story.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/features/onboarding/data/drift_first_session_store.dart';
import 'package:wassal/features/onboarding/domain/first_session.dart';
import 'package:wassal/features/onboarding/onboarding_providers.dart';
import 'package:wassal/features/onboarding/presentation/scene_player.dart';

import '../../../helpers/content.dart';
import '../../../helpers/economy.dart';
import '../../../helpers/pump_app.dart';
import '../../../helpers/design_component.dart';
import '../../../helpers/routing.dart';
import '../../../helpers/trip.dart';
import '../../../helpers/tutorial_content.dart';

// The comic player (specs/012-m07-onboarding/contracts/scenes.md "The
// player") and the opening's page (`/onboarding/intro`).

Scene get _opening => sceneOf(sampleContent(), 'opening')!;

int _dotIndex(WidgetTester tester) =>
    tester.widget<PageDots>(find.byType(PageDots)).index;

/// Pumps the player on the sample's opening scene; returns how many times
/// it finished.
Future<List<void>> _pumpPlayer(
  WidgetTester tester, {
  bool reducedMotion = false,
}) async {
  final finished = <void>[];
  await pumpDesignComponent(
    tester,
    ScenePlayer(
      title: 'أول شغلانة',
      scene: _opening,
      driverName: 'الأسطى',
      onFinished: () => finished.add(null),
    ),
    reducedMotion: reducedMotion,
    center: false,
  );
  await tester.pumpAndSettle();
  return finished;
}

/// Every label in the semantics tree under [node], in traversal order.
List<String> _readOrder(SemanticsNode node) {
  final labels = <String>[];
  void visit(SemanticsNode n) {
    // Numbers arrive in bidi isolates (NumberFormatter); read without them.
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

void main() {
  group('ScenePlayer', () {
    testWidgets('«يلا» advances one panel; on the last it finishes', (
      tester,
    ) async {
      final finished = await _pumpPlayer(tester);
      expect(_dotIndex(tester), 0);
      for (final expected in [1, 2]) {
        await tester.tap(find.byKey(ScenePlayer.nextKey));
        await tester.pumpAndSettle();
        expect(_dotIndex(tester), expected);
        expect(finished, isEmpty);
      }
      await tester.tap(find.byKey(ScenePlayer.nextKey));
      await tester.pumpAndSettle();
      expect(finished, hasLength(1));
      expect(_dotIndex(tester), 2, reason: 'the last panel stays');
    });

    testWidgets('«تخطّى» finishes at once, and only once', (tester) async {
      final finished = await _pumpPlayer(tester);
      await tester.tap(find.byKey(ScenePlayer.skipKey));
      await tester.pumpAndSettle();
      expect(finished, hasLength(1));
      expect(_dotIndex(tester), 0);
      await tester.tap(find.byKey(ScenePlayer.skipKey));
      await tester.tap(find.byKey(ScenePlayer.nextKey));
      await tester.pumpAndSettle();
      expect(finished, hasLength(1));
    });

    testWidgets('back finishes at once', (tester) async {
      final finished = await _pumpPlayer(tester);
      await pressBack(tester);
      expect(finished, hasLength(1));
    });

    testWidgets('the narrator line is the caption chip; two speaking lines '
        'make two bubbles', (tester) async {
      await _pumpPlayer(tester);
      final panel = tester.widget<ComicPanel>(find.byType(ComicPanel));
      expect(panel.caption, 'الموقف، الصبح بدري');
      expect(panel.lines, [
        ('المعلم', 'خد مفتاح التوكتوك. لمّ الأجرة صح، والباقي يرجع لصاحبه.'),
      ]);
      expect(find.byKey(ComicPanel.captionKey), findsOneWidget);
      expect(find.byKey(ComicPanel.bubbleKey(0)), findsOneWidget);
      expect(find.byKey(ComicPanel.bubbleKey(1)), findsNothing);

      await tester.tap(find.byKey(ScenePlayer.nextKey));
      await tester.pumpAndSettle();
      final second = tester.widget<ComicPanel>(find.byType(ComicPanel));
      expect(second.caption, isNull);
      expect(second.lines, [
        ('المعلم', 'الركاب بيدفعوا، والفلوس بتيجي لحد الدرج.'),
        ('الأسطى', 'وأنا أرجّع الباقي لكل واحد.'),
      ], reason: "the driver's line carries the driver's name");
      expect(find.byKey(ComicPanel.bubbleKey(1)), findsOneWidget);
    });

    testWidgets('the read order: title, caption, speaker and line, the '
        'dots, «يلا», «تخطّى»', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pumpPlayer(tester);
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
      expect(
        positions,
        everyElement(greaterThanOrEqualTo(0)),
        reason: '$order',
      );
      expect(
        positions,
        [...positions]..sort(),
        reason: 'read order was $order',
      );
      expect(
        order[positions[2]],
        contains('خد مفتاح التوكتوك'),
        reason: 'the speaker and the line read together',
      );
      semantics.dispose();
    });

    testWidgets('a panel change slides and fades within sheetIn', (
      tester,
    ) async {
      await _pumpPlayer(tester);
      await tester.tap(find.byKey(ScenePlayer.nextKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 140));
      expect(
        find.descendant(
          of: find.byKey(ScenePlayer.panelKey),
          matching: find.byType(SlideTransition),
        ),
        findsWidgets,
      );
      await tester.pump(const Duration(milliseconds: 141));
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('reduced motion: a 150 ms fade, no slide', (tester) async {
      await _pumpPlayer(tester, reducedMotion: true);
      final panelArea = find.byKey(ScenePlayer.panelKey);
      expect(
        tester
            .widget<AnimatedSwitcher>(
              find.descendant(
                of: panelArea,
                matching: find.byType(AnimatedSwitcher),
              ),
            )
            .duration,
        DesignExtras.panelFadeReduced,
      );
      await tester.tap(find.byKey(ScenePlayer.nextKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      expect(
        find.descendant(of: panelArea, matching: find.byType(SlideTransition)),
        findsNothing,
      );
      expect(
        find.descendant(of: panelArea, matching: find.byType(FadeTransition)),
        findsWidgets,
      );
      await tester.pumpAndSettle();
      expect(_dotIndex(tester), 1);
    });
  });

  group('the opening page', () {
    testWidgets('finishing the opening marks it done and goes to the Name '
        'card', (tester) async {
      final economy = await testEconomy();
      await pumpWassalApp(
        tester,
        newPlayer: true,
        economy: economyOverridesOf(economy),
      );
      expect(currentLocation(tester), '/onboarding/intro');
      expect(find.byType(ScenePlayer), findsOneWidget);
      expect(
        (await DriftFirstSessionStore(economy.db).read()).openingDoneAtMs,
        isNull,
      );
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byKey(ScenePlayer.nextKey));
        await tester.pumpAndSettle();
      }
      expect(currentLocation(tester), '/onboarding/name');
      expect(
        (await DriftFirstSessionStore(economy.db).read()).openingDoneAtMs,
        isNotNull,
      );
    });

    testWidgets('«تخطّى» does the same', (tester) async {
      final economy = await testEconomy();
      await pumpWassalApp(
        tester,
        newPlayer: true,
        economy: economyOverridesOf(economy),
      );
      await tester.tap(find.byKey(ScenePlayer.skipKey));
      await tester.pumpAndSettle();
      expect(currentLocation(tester), '/onboarding/name');
      expect(
        (await DriftFirstSessionStore(economy.db).read()).openingDoneAtMs,
        isNotNull,
      );
    });

    testWidgets('opening it writes step 1, never lowering a later one', (
      tester,
    ) async {
      final economy = await testEconomy();
      final container = await pumpWassalApp(
        tester,
        newPlayer: true,
        economy: economyOverridesOf(economy),
      );
      expect(container.read(firstSessionFlagsProvider).value?.stepReached, 1);
      expect(
        (await DriftFirstSessionStore(economy.db).read()).stepReached,
        openingStep,
      );

      await DriftFirstSessionStore(economy.db).reachStep(3);
      container.read(routerProvider).go('/onboarding/intro');
      await tester.pumpAndSettle();
      expect((await DriftFirstSessionStore(economy.db).read()).stepReached, 3);
    });

    testWidgets('a pack without an opening scene goes to the Name card', (
      tester,
    ) async {
      final container = await pumpWassalApp(
        tester,
        newPlayer: true,
        content: contentTestOverrides(assets: noSessionScenesAssets()),
      );
      expect(currentLocation(tester), '/onboarding/name');
      container.read(routerProvider).go('/onboarding/intro');
      await tester.pumpAndSettle();
      expect(currentLocation(tester), '/onboarding/name');
      expect(container.read(firstSessionFlagsProvider).value?.stepReached, 1);
    });
  });
}
