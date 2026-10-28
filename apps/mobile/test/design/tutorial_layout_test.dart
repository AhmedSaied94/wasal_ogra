import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/components/app_icon.dart';
import 'package:wassal/core/theme/components/story.dart';
import 'package:wassal/features/onboarding/domain/tutorial_coach.dart';
import 'package:wassal/features/onboarding/presentation/coach_layer.dart';
import 'package:wassal/features/trip/presentation/dashboard/boosters_locked_bar.dart';
import 'package:wassal/features/trip/presentation/dashboard/tray.dart';

import 'boxes.dart';
import 'design_check.dart';
import 'samples/tutorial.dart';

// `Tutorial` against its measured boxes (contracts/design-checks.md; M07
// contracts/coach.md "The overlay"). While a step shows, a screen reader
// reaches only its target, so the «١» cell is the one tap node, paired
// with box 34; the artboard's other taps are C-Trip's controls under the
// scrim, which C-Trip's layout test checks on the same dashboard. Then the
// coach's parts as rects: the hole on the cell, the hand (58), بلية (57),
// his bubble (53), and the locked bar (48) with its lock (49). Still, so
// the hand doesn't bob.

const _underScrim =
    'under the coach only its target reaches a screen reader (FR-024); '
    'the control is C-Trip\'s, checked there';

/// The artboard's taps other than the «١» cell.
const _scrimmed = [1, 26, 29, 32, 36, 38, 40, 42, 44, 46];

const _cellBox = 34;

Future<void> _pumpStill(WidgetTester tester) async {
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  await pumpTutorial(tester);
}

void main() {
  testWidgets('Tutorial: the boxes', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pumpStill(tester);
    final target = find.byKey(CoachLayer.targetKey(const TrayCellTarget(100)));
    expectLayoutMatches(
      tester,
      'Tutorial',
      skip: {for (final id in _scrimmed) id: _underScrim},
      // The fixture's drawer holds what the artboard's does in this cell.
      pairings: {_cellBox: tester.getSemantics(target).label},
    );
    semantics.dispose();
  });

  testWidgets('Tutorial: the hole, the hand, بلية, his bubble and the '
      'locked bar', (tester) async {
    await _pumpStill(tester);
    final board = loadBoard('Tutorial');
    Rect box(int id) {
      final b = board.boxes.firstWhere((b) => b.id == id);
      return Rect.fromLTWH(b.x, b.y, b.w, b.h);
    }

    void within(Rect app, Rect design, String what) {
      for (final (a, d, side) in [
        (app.left, design.left, 'left'),
        (app.top, design.top, 'top'),
        (app.right, design.right, 'right'),
        (app.bottom, design.bottom, 'bottom'),
      ]) {
        expect(
          a,
          closeTo(d, 2),
          reason: '$what $side: app $app, design $design',
        );
      }
    }

    final cell = tester.getRect(find.byKey(Tray.slotKey(100)));
    within(cell, box(_cellBox), 'cell');
    expect(tester.widget<CoachMark>(find.byType(CoachMark)).target, cell);
    within(
      tester.getRect(
        find.descendant(
          of: find.byType(CoachMark),
          matching: find.byType(CoachHand),
        ),
      ),
      box(58),
      'hand',
    );
    within(tester.getRect(find.byKey(CoachLayer.headKey)), box(57), 'head');
    within(tester.getRect(find.byKey(CoachLayer.bubbleKey)), box(53), 'bubble');
    within(tester.getRect(find.byType(BoostersLockedBar)), box(48), 'bar');
    within(
      tester.getRect(
        find.descendant(
          of: find.byType(BoostersLockedBar),
          matching: find.byType(AppIcon),
        ),
      ),
      box(49),
      'lock',
    );
  });
}
