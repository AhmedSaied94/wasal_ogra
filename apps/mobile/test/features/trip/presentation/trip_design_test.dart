import 'package:content_models/content_models.dart';
import 'package:flame/game.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/core/l10n/number_formatter.dart';
import 'package:wassal/core/theme/components/buttons.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/trip/application/trip_controller.dart';
import 'package:wassal/features/trip/domain/scene_layout.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';
import 'package:wassal/features/trip/presentation/dashboard/boosters_row.dart';
import 'package:wassal/features/trip/presentation/dashboard/dashboard.dart';
import 'package:wassal/features/trip/presentation/dashboard/hand_slot.dart';
import 'package:wassal/features/trip/presentation/dashboard/tray.dart';
import 'package:wassal/features/trip/presentation/overlays/bubbles_layer.dart';
import 'package:wassal/features/trip/presentation/overlays/hit_areas.dart';
import 'package:wassal/features/trip/presentation/overlays/patches_layer.dart';
import 'package:wassal/features/trip/presentation/overlays/token_layer.dart';
import 'package:wassal/features/trip/presentation/scene/trip_game.dart';
import 'package:wassal/features/trip/presentation/top_bar/station_strip_bar.dart';
import 'package:wassal/features/trip/presentation/top_bar/top_bar.dart';
import 'package:wassal/features/trip/presentation/trip_scope.dart';
import 'package:wassal/features/trip/presentation/trip_text.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

import '../../../design/samples/c_trip.dart';
import '../../../helpers/design_component.dart';
import '../../../helpers/trip.dart';

// The trip's components in the new look (specs/008.5-m21-design-refresh,
// HANDOFF §3.4, tasks.md T061): the HUD, the strip, tags, notes, bubbles,
// the hand, tray cells and boosters, the passengers' labels, and the same
// commands as before.

const numbers = NumberFormatter(DigitStyle.arabicIndic);

AppLocalizations l10nOf(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(TripDashboard)));

/// The colours [finder]'s boxes are filled with.
Set<Color?> fills(WidgetTester tester, Finder finder) => {
  for (final box in tester.widgetList<DecoratedBox>(
    find.descendant(of: finder, matching: find.byType(DecoratedBox)),
  ))
    if (box.decoration case BoxDecoration(:final color)) color,
};

/// The shadows drawn under [finder]'s boxes.
List<BoxShadow> shadows(WidgetTester tester, Finder finder) => [
  for (final box in tester.widgetList<DecoratedBox>(
    find.descendant(of: finder, matching: find.byType(DecoratedBox)),
  ))
    if (box.decoration case BoxDecoration(:final boxShadow?)) ...boxShadow,
];

/// The last command applied, as the log writes it, without its time.
List<Object?> lastCommand(TripController c) =>
    c.engine!.commandLog.last.toJson().sublist(1);

void main() {
  group('TripHud', () {
    testWidgets('pause is an IconCircleButton; the title is one line', (
      tester,
    ) async {
      await pumpCTrip(tester);
      final l10n = l10nOf(tester);
      expect(
        tester.widget(find.byKey(TripHud.pauseKey)),
        isA<IconCircleButton>(),
      );
      final title = tester.widget<Text>(find.byKey(TripHud.titleKey));
      expect(title.data, l10n.tripHudTitle('خط الجامعة', numbers.integer(12)));
      expect(title.maxLines, 1);
      expect(title.overflow, TextOverflow.ellipsis);
    });

    testWidgets('ReputationBar turns danger under 40% with «تحت ٤٠٪»', (
      tester,
    ) async {
      await pumpCTrip(tester);
      final l10n = l10nOf(tester);
      final low = l10n.tripReputationLow(numbers.integer(40));
      final bar = find.byType(ReputationBar);
      expect(fills(tester, bar), contains(ColorTokens.primary));
      expect(fills(tester, bar), isNot(contains(ColorTokens.danger)));
      expect(find.text(low), findsNothing);
      expect(find.text(l10n.tripReputationLabel), findsOneWidget);

      await showTripView(tester, cTripView(reputation: 30));
      expect(fills(tester, bar), contains(ColorTokens.danger));
      expect(fills(tester, bar), isNot(contains(ColorTokens.primary)));
      expect(find.text(low), findsOneWidget);
    });
  });

  group('StationStrip', () {
    testWidgets('dots by time, in their colours and letters', (tester) async {
      await pumpCTrip(tester);
      final l10n = l10nOf(tester);
      final track = tester.getRect(find.byKey(StationStrip.trackKey));
      expect(track.width, closeTo(302, 0.5));
      // RTL: the start end is the right; الجامعة (the last) at the left.
      for (final (slot, share) in [(0, 0.36), (1, 0.68), (2, 1.0)]) {
        final dot = find.byKey(StationStrip.dotKey(slot));
        expect(
          tester.getCenter(dot).dx,
          closeTo(track.right - 302 * share, 0.5),
          reason: 'stop $slot',
        );
        expect(tester.getSize(dot), const Size.square(24));
        expect(
          fills(tester, dot),
          contains(StationColors.all[slot].bg),
          reason: 'stop $slot',
        );
        expect(
          find.descendant(
            of: dot,
            matching: find.text(l10n.stationLetter(slot)),
          ),
          findsOneWidget,
        );
      }
      // The vehicle at 24%, the fill from the start end to it.
      expect(
        tester.getCenter(find.byKey(StationStrip.vehicleKey)).dx,
        closeTo(track.right - 302 * 0.24, 0.5),
      );
      expect(
        tester.getSize(find.byKey(StationStrip.vehicleKey)),
        const Size(28, 26),
      );
    });

    testWidgets('the next stop: a 3 pt ring and its countdown chip', (
      tester,
    ) async {
      await pumpCTrip(tester);
      final l10n = l10nOf(tester);
      final ring = shadows(tester, find.byKey(StationStrip.dotKey(0)));
      expect(
        ring.where((s) => s.spreadRadius == 3 && s.color == ColorTokens.danger),
        hasLength(1),
      );
      expect(shadows(tester, find.byKey(StationStrip.dotKey(1))), isEmpty);
      final chip = find.byKey(StationStrip.countdownKey);
      expect(
        find.descendant(
          of: chip,
          matching: find.text(l10n.tripSeconds(numbers.integer(18))),
        ),
        findsOneWidget,
      );
      expect(fills(tester, chip), contains(ColorTokens.danger));
      // 18 s left: steady.
      expect(
        find.ancestor(of: chip, matching: find.byType(TripPulse)),
        findsNothing,
      );
    });

    testWidgets('under 8 s the chip pulses; steady under reduced motion', (
      tester,
    ) async {
      await pumpCTrip(tester);
      // A quarter into the pulse's cycle, its scale is off 1.
      final view = cTripView(tMs: 36250, strip: cTripStrip(countdownMs: 7000));
      await showTripView(tester, view);
      final chip = find.byKey(StationStrip.countdownKey);
      Finder scaled() => find.ancestor(
        of: chip,
        matching: find.byWidgetPredicate(
          (w) =>
              w is Transform &&
              (w.transform.getMaxScaleOnAxis() - 1).abs() > 0.01,
        ),
      );
      expect(
        find.ancestor(of: chip, matching: find.byType(TripPulse)),
        findsOneWidget,
      );
      expect(scaled(), findsOneWidget);

      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await tester.pump();
      expect(scaled(), findsNothing);
    });

    testWidgets('a passed stop fades to 35% and reads «عدّت»', (tester) async {
      await pumpCTrip(tester);
      final l10n = l10nOf(tester);
      await showTripView(tester, cTripView(strip: cTripStrip(next: 1)));
      final passed = find.ancestor(
        of: find.byKey(StationStrip.dotKey(0)),
        matching: find.byWidgetPredicate(
          (w) => w is Opacity && w.opacity == 0.35,
        ),
      );
      expect(passed, findsOneWidget);
      expect(find.text(l10n.tripStationPassed), findsOneWidget);
    });

    testWidgets('a raised fare: the old one struck through, the new chip', (
      tester,
    ) async {
      await pumpCTrip(tester);
      final l10n = l10nOf(tester);
      await showTripView(tester, cTripView(strip: cTripStrip(raisedFrom: 300)));
      final old = tester.widget<Text>(
        find.text(l10n.tripStripFare(numbers.piasters(300))),
      );
      expect(old.style?.decoration, TextDecoration.lineThrough);
      final raised = find.byKey(StationStrip.raisedKey(0));
      expect(
        find.descendant(
          of: raised,
          matching: find.text(l10n.tripStripFare(numbers.piasters(450))),
        ),
        findsOneWidget,
      );
      expect(fills(tester, raised), contains(ColorTokens.dangerSoft));
    });
  });

  group('StationTag', () {
    testWidgets('24, 26 and 30 by row; hot while next and owed', (
      tester,
    ) async {
      await pumpCTrip(tester);
      for (final s in cTripSeats) {
        final tag = find.byKey(PatchesLayer.tagKey('p_${s.seatId}'));
        final expected = switch (s.seatId[0]) {
          'C' => 24.0,
          'B' => 26.0,
          _ => 30.0,
        };
        expect(tester.getSize(tag), Size.square(expected), reason: s.seatId);
        expect(
          tester.widget<StationTag>(tag).hot,
          s.seatId == 'C_l',
          reason: s.seatId,
        );
      }
    });

    testWidgets('sits at its seat: face + (−38, +46) × rig scale', (
      tester,
    ) async {
      await pumpCTrip(tester);
      // Box 26: the back-left tag, 24 at (90, 108) in the scene at y 158.
      final rect = tester.getRect(find.byKey(PatchesLayer.tagKey('p_C_l')));
      expect(rect.left, closeTo(90.25, 1));
      expect(rect.top, closeTo(158 + 108.75, 1));
    });
  });

  group('MoneyNote', () {
    for (final (kind, bg, lip) in [
      (MoneyNoteKind.fare, ColorTokens.noteFare, ColorTokens.noteFareLip),
      (MoneyNoteKind.change, ColorTokens.noteChange, ColorTokens.noteChangeLip),
      (
        MoneyNoteKind.blocked,
        ColorTokens.noteBlocked,
        ColorTokens.noteBlockedLip,
      ),
      (MoneyNoteKind.inHand, ColorTokens.noteInHand, ColorTokens.noteInHandLip),
    ]) {
      testWidgets('${kind.name}: its colours, 26 high, at least 42 wide', (
        tester,
      ) async {
        await pumpDesignComponent(
          tester,
          MoneyNote(kind: kind, amount: numbers.piasters(1000)),
        );
        final note = find.byType(MoneyNote);
        expect(fills(tester, note), contains(bg));
        expect(shadows(tester, note).map((s) => s.color), contains(lip));
        final size = tester.getSize(find.byKey(MoneyNote.bodyKey));
        expect(size.height, 26);
        expect(size.width, greaterThanOrEqualTo(42));
        final digits = tester.widget<Text>(
          find.descendant(
            of: note,
            matching: find.text(numbers.piasters(1000)),
          ),
        );
        expect(digits.style?.fontSize, 16);
        expect(
          find.descendant(of: note, matching: find.text('؟')),
          kind == MoneyNoteKind.blocked ? findsOneWidget : findsNothing,
        );
      });
    }

    testWidgets('fallen: a 4 pt sun.glow ring (Components box 120)', (
      tester,
    ) async {
      await pumpDesignComponent(
        tester,
        MoneyNote(kind: MoneyNoteKind.fallen, amount: numbers.piasters(500)),
      );
      final ring = shadows(tester, find.byType(MoneyNote));
      expect(
        ring.where(
          (s) => s.color == ColorTokens.sunGlow && s.spreadRadius == 4,
        ),
        isNotEmpty,
      );
    });

    testWidgets('in the scene, notes in flight and the hand at 15.5', (
      tester,
    ) async {
      await pumpCTrip(tester);
      final kinds = tester
          .widgetList<MoneyNote>(find.byType(MoneyNote))
          .map((n) => n.kind)
          .toList();
      expect(
        kinds,
        containsAll([
          MoneyNoteKind.fare,
          MoneyNoteKind.blocked,
          MoneyNoteKind.inHand,
        ]),
      );
    });
  });

  group('SpeechBubble', () {
    for (final (variant, bg) in [
      (SpeechBubbleVariant.normal, ColorTokens.paper),
      (SpeechBubbleVariant.warn, ColorTokens.dangerSoft),
      (SpeechBubbleVariant.fight, ColorTokens.danger),
      (SpeechBubbleVariant.thanks, ColorTokens.primarySoft),
      (SpeechBubbleVariant.character, ColorTokens.paper),
    ]) {
      testWidgets('${variant.name}: its fill, 16 pt text never scaled', (
        tester,
      ) async {
        await pumpDesignComponent(
          tester,
          SpeechBubble(
            text: 'الباقي يا أسطى!',
            variant: variant,
            name: variant == SpeechBubbleVariant.character ? 'بلية' : null,
          ),
          textScale: 1.3,
        );
        final bubble = find.byType(SpeechBubble);
        expect(fills(tester, bubble), contains(bg));
        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(of: bubble, matching: find.byType(RichText)).last,
        );
        expect(paragraph.textScaler.scale(16), 16);
        expect(
          find.descendant(of: bubble, matching: find.text('بلية')),
          variant == SpeechBubbleVariant.character
              ? findsOneWidget
              : findsNothing,
        );
      });
    }

    testWidgets('at most 2; the tail 8 pt above the head; clamped inside', (
      tester,
    ) async {
      await pumpCTrip(tester);
      await showTripView(
        tester,
        cTripView(
          bubbles: const [
            BubbleView(
              passengerId: 'p_A_l',
              text: 'يا أسطى نزّلني عند المستشفى لو سمحت',
              style: BubbleStyle.plain,
              shownAtMs: 35000,
            ),
            BubbleView(
              passengerId: 'p_C_m',
              text: 'هه؟',
              style: BubbleStyle.plain,
              shownAtMs: 35100,
            ),
            BubbleView(
              passengerId: 'p_C_r',
              text: 'خد ١٠، طالب',
              style: BubbleStyle.plain,
              shownAtMs: 35200,
            ),
          ],
        ),
      );
      final bubbles = find.byType(SpeechBubble);
      expect(bubbles, findsNWidgets(2));
      final scene = sceneRect(tester);
      for (final rect in [
        for (final e in bubbles.evaluate())
          tester.getRect(find.byWidget(e.widget)),
      ]) {
        expect(rect.left, greaterThanOrEqualTo(scene.left + 10 - 0.5));
        expect(rect.right, lessThanOrEqualTo(scene.right - 10 + 0.5));
      }
      // The back-middle sleeper's line: its tail's tip 8 pt above his head.
      final tail = find.byKey(SpeechBubble.tailKey('p_C_m'));
      final layout = microOldLayout(scene.size);
      expect(
        tester.getRect(tail).bottom,
        closeTo(scene.top + layout.seats['C_m']!.bubbleAnchor.y, 1.5),
      );
    });
  });

  group('HandSlot', () {
    testWidgets('«فاضية» when empty; chips and the total in hand', (
      tester,
    ) async {
      await pumpCTrip(tester);
      final l10n = l10nOf(tester);
      final slot = find.byKey(HandSlot.slotKey);
      expect(
        find.descendant(
          of: slot,
          matching: find.text(l10n.tripHandTotal(numbers.piasters(1550))),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: slot, matching: find.byKey(HandSlot.chipKey(1000))),
        findsOneWidget,
      );
      expect(
        find.descendant(of: slot, matching: find.byKey(HandSlot.chipKey(50))),
        findsOneWidget,
      );
      await showTripView(
        tester,
        cTripView(hand: const HandView(pieces: {}, totalPiasters: 0)),
      );
      expect(
        find.descendant(of: slot, matching: find.text(l10n.tripHandEmpty)),
        findsOneWidget,
      );
    });

    testWidgets('«رجّع» sits inside the hand only in the undo window', (
      tester,
    ) async {
      await pumpCTrip(tester);
      expect(find.byKey(UndoButton.buttonKey), findsNothing);
      await showTripView(tester, cTripView(undoUntilMs: 37000));
      final undo = find.byKey(UndoButton.buttonKey);
      expect(undo, findsOneWidget);
      final hit = tester.getRect(undo);
      expect(hit.width, greaterThanOrEqualTo(44));
      expect(hit.height, greaterThanOrEqualTo(44));
      final hand = tester.getRect(find.byKey(HandSlot.slotKey));
      // At the hand's end side: its left in RTL.
      expect(hit.center.dx, lessThan(hand.center.dx));
      expect(hand.inflate(1).contains(hit.center), isTrue);
    });

    testWidgets('CallChangeButton: a sun button with «×٢», disabled at 0', (
      tester,
    ) async {
      await pumpCTrip(tester);
      final l10n = l10nOf(tester);
      final call = find.byKey(CallChangeButton.buttonKey);
      expect(fills(tester, call), contains(ColorTokens.sun));
      expect(
        find.descendant(
          of: call,
          matching: find.text(l10n.tripTimes(numbers.integer(2))),
        ),
        findsOneWidget,
      );
      await showTripView(
        tester,
        cTripView(breakButton: const BreakButtonView(left: 0, enabled: false)),
      );
      expect(
        find.ancestor(
          of: find.text(l10n.tripBreakButton),
          matching: find.byWidgetPredicate(
            (w) => w is Opacity && w.opacity == 0.45,
          ),
        ),
        findsOneWidget,
      );
    });
  });

  group('TrayCell', () {
    testWidgets('full, empty, breakable and pressed', (tester) async {
      await pumpCTrip(tester);
      final full = find.byKey(Tray.slotKey(500));
      final empty = find.byKey(Tray.slotKey(10000));
      expect(fills(tester, full), contains(ColorTokens.paper));
      expect(
        shadows(tester, full).map((s) => s.color),
        contains(LipTokens.trayCell.color),
      );
      expect(
        tester
            .widget<TrayCell>(
              find.descendant(of: empty, matching: find.byType(TrayCell)),
            )
            .state,
        TrayCellState.empty,
      );
      expect(fills(tester, empty), isNot(contains(ColorTokens.paper)));

      await showTripView(
        tester,
        cTripView(
          breakMode: true,
          tray: [
            for (final (d, n) in [
              (50, 1),
              (100, 3),
              (500, 1),
              (1000, 1),
              (2000, 1),
              (5000, 1),
              (10000, 0),
              (20000, 0),
            ])
              TraySlotView(
                denomination: d,
                count: n,
                breakable: d >= 1000 && n > 0,
              ),
          ],
        ),
      );
      final ring = shadows(tester, find.byKey(Tray.slotKey(1000)));
      expect(
        ring.where((s) => s.color == ColorTokens.danger && s.spreadRadius == 3),
        hasLength(1),
      );
      expect(
        shadows(
          tester,
          find.byKey(Tray.slotKey(500)),
        ).where((s) => s.color == ColorTokens.danger),
        isEmpty,
      );

      // Pressed: the lip goes to 0.
      final gesture = await tester.startGesture(tester.getCenter(full));
      // The tap-down lands after the press timeout; the press runs from the
      // next frame.
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump(const Duration(milliseconds: 150));
      expect(
        shadows(tester, full).where((s) => s.color == LipTokens.trayCell.color),
        isEmpty,
      );
      await gesture.up();
      await tester.pumpAndSettle();
    });
  });

  group('BoosterButton', () {
    testWidgets('count, price «N بون» and the active timer; no ad badge', (
      tester,
    ) async {
      await pumpCTrip(tester);
      final l10n = l10nOf(tester);
      final bag = find.byKey(BoostersRow.slotKey(BoosterId.changeBag));
      expect(
        find.descendant(
          of: bag,
          matching: find.text(l10n.tripTimes(numbers.integer(1))),
        ),
        findsOneWidget,
      );
      final jam = find.byKey(BoostersRow.slotKey(BoosterId.trafficJam));
      expect(
        find.descendant(
          of: jam,
          matching: find.text(l10n.tripBoosterPriceBadge(numbers.integer(5))),
        ),
        findsOneWidget,
      );
      // The ad badge waits for M11 (spec FR-029): one badge, the price.
      expect(
        find.descendant(of: jam, matching: find.byType(BoosterBadge)),
        findsOneWidget,
      );

      await showTripView(
        tester,
        cTripView(
          boosters: const [
            BoosterSlotView(
              booster: BoosterId.ledgerPeek,
              count: 0,
              priceBonat: 8,
              enabled: false,
              adOffered: false,
              activeUntilMs: 40000,
            ),
          ],
        ),
      );
      final ledger = find.byKey(BoostersRow.slotKey(BoosterId.ledgerPeek));
      expect(
        find.descendant(
          of: ledger,
          matching: find.text(l10n.tripSeconds(numbers.integer(4))),
        ),
        findsOneWidget,
      );
    });
  });

  group('labels', () {
    testWidgets("a passenger's label: look and stop, «ليه باقي» while hot", (
      tester,
    ) async {
      await pumpCTrip(tester);
      final l10n = l10nOf(tester);
      final owed = tester.getSemantics(find.byKey(HitAreas.keyOf('p_C_l')));
      expect(owed.label, contains('الكوبري'));
      expect(owed.label, endsWith('ليه باقي'));
      final calm = tester.getSemantics(find.byKey(HitAreas.keyOf('p_A_l')));
      expect(calm.label, contains(l10n.tripLookHajja));
      expect(calm.label, contains('المستشفى'));
      expect(calm.label, isNot(contains('ليه باقي')));
    });
  });

  group('commands', () {
    testWidgets('each control sends the command it sent before', (
      tester,
    ) async {
      // C-Trip's trip starts with notes the drawer can break.
      await pumpTrip(tester, tripId: cTripId);
      final c = controllerOf(tester);
      await tester.tap(find.byKey(Tray.slotKey(500)));
      await tester.pump();
      expect(lastCommand(c), ['PickFromTray', 500]);
      await tester.tap(find.byKey(HandSlot.slotKey));
      await tester.pump();
      expect(lastCommand(c), ['ReturnHand']);
      await tester.tap(find.byKey(CallChangeButton.buttonKey));
      await tester.pump();
      expect(c.view!.breakMode, isTrue);
      final note = c.view!.tray.firstWhere((s) => s.breakable).denomination;
      await tester.tap(find.byKey(Tray.slotKey(note)));
      await tester.pump();
      expect(lastCommand(c), ['RequestBreak', note]);
      for (var i = 0; i < 2000 && c.view!.passengers.isEmpty; i++) {
        advanceMs(c, 33);
      }
      await tester.pump();
      final p = c.view!.passengers.first.passengerId;
      await tester.tap(find.byKey(HitAreas.keyOf(p)), warnIfMissed: false);
      await tester.pump();
      expect(lastCommand(c).first, anyOf('Tap', 'SendHand'));
    });
  });
}

/// The `micro_old` layout of a scene of [size].
SceneLayout microOldLayout(Size size) => SceneLayout(
  sampleTrip(cTripId).seats,
  vehicle: VehicleId.microOld,
  width: size.width,
  height: size.height,
);

/// The scene's rect on screen.
Rect sceneRect(WidgetTester tester) =>
    tester.getRect(find.byType(GameWidget<TripGame>));
