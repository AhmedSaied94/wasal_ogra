import 'package:content_models/content_models.dart';
import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/components/story.dart';
import 'package:wassal/features/trip/domain/scene_layout.dart';
import 'package:wassal/features/trip/presentation/dashboard/boosters_row.dart';
import 'package:wassal/features/trip/presentation/dashboard/dashboard.dart';
import 'package:wassal/features/trip/presentation/overlays/hint_layer.dart';
import 'package:wassal/features/trip/presentation/scene/trip_game.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

import '../helpers/trip.dart';
import 'boxes.dart';
import 'design_check.dart';
import 'samples/tutorial_hint.dart';
import 'trip_labels.dart';

// `Tutorial`'s hint against its measured boxes (contracts/design-checks.md
// "Skips and pairings"): the HUD and the dashboard's taps, then بلية's head,
// his bubble and the hand as rects (HANDOFF `Tutorial` blocks 5–7). The
// scrim, the hole and the locked boosters are M07's, so the app's boosters
// and riders are app-only here. The hand points at a passenger, not the
// artboard's tray cell, so its placement is checked against its target.

const _noMegaphone =
    'the artboard drops the megaphone; the app keeps C-Trip\'s call button';

void main() {
  testWidgets('Tutorial: the boxes', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpTutorialHint(tester);
    final l10n = AppLocalizations.of(
      tester.element(find.byType(TripDashboard)),
    );
    expectLayoutMatches(
      tester,
      'Tutorial',
      skip: {26: _noMegaphone, 29: _noMegaphone},
      appOnly: {
        l10n.tripDebugOpen,
        ...megaphoneLabels(tester),
        for (final b in BoosterId.values)
          if (find.byKey(BoostersRow.slotKey(b)).evaluate().isNotEmpty)
            tester.getSemantics(find.byKey(BoostersRow.slotKey(b))).label,
        ...passengerLabels(tester, [
          for (final p in tutorialView().passengers) p.passengerId,
        ]),
      },
    );
    semantics.dispose();
  });

  testWidgets('Tutorial: بلية, his bubble and the hand', (tester) async {
    await pumpTutorialHint(tester);
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

    within(tester.getRect(find.byKey(HintLayer.headKey)), box(57), 'head');
    within(tester.getRect(find.byKey(HintLayer.bubbleKey)), box(53), 'bubble');

    final scene = tester.getRect(find.byType(GameWidget<TripGame>));
    final definition = sampleTrip(tutorialTripId);
    final face = SceneLayout(
      definition.seats,
      vehicle: definition.vehicleId,
      width: scene.width,
      height: scene.height,
    ).seats['A_m']!.head;
    final target = Rect.fromLTWH(
      scene.left + face.left,
      scene.top + face.top,
      face.width,
      face.height,
    );
    // The artboard's hand points up at its cell (box 34) from box 58; the
    // app's points the same way at its target, unless that would cover
    // the bubble, as it does on the tuktuk, where it points down.
    final cell = box(34);
    expect(CoachHand.placeFor(cell), box(58).topLeft);
    final hand = tester.getRect(find.byKey(HintLayer.pointerKey));
    final below = CoachHand.placeFor(target) & CoachHand.size;
    final bubble = tester.getRect(find.byKey(HintLayer.bubbleKey));
    expect(below.overlaps(bubble), isTrue);
    within(hand, CoachHand.placeAbove(target) & CoachHand.size, 'hand');
    expect(hand.overlaps(bubble), isFalse);
  });
}
