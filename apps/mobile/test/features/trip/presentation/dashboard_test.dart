import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/core/l10n/number_formatter.dart';
import 'package:wassal/features/trip/application/trip_controller.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';
import 'package:wassal/features/trip/presentation/dashboard/hand_slot.dart';
import 'package:wassal/features/trip/presentation/dashboard/talk_log_view.dart';
import 'package:wassal/features/trip/presentation/dashboard/tray.dart';
import 'package:wassal/features/trip/presentation/overlays/hit_areas.dart';
import 'package:wassal/features/trip/presentation/trip_scope.dart';
import 'package:wassal/features/trip/presentation/trip_text.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

import '../../../helpers/trip.dart';

// The dashboard's controls (tasks.md T032, ux-spec «التابلوه»).

/// The last command applied, as the log writes it, without its time.
List<Object?> lastCommand(TripController c) =>
    c.engine!.commandLog.last.toJson().sublist(1);

/// Advances until [passengerId] sits in the scene, tappable.
Future<void> untilAboard(
  WidgetTester tester,
  TripController c,
  String passengerId,
) async {
  for (var i = 0; i < 2000; i++) {
    if (c.view!.passenger(passengerId)?.presence == PresenceView.aboard) break;
    advanceMs(c, 33);
  }
  await tester.pump();
}

void main() {
  testWidgets('a tap on a drawer slot picks that denomination', (tester) async {
    await pumpTrip(tester);
    final c = controllerOf(tester);
    await tester.tap(find.byKey(Tray.slotKey(500)));
    await tester.pump();
    expect(lastCommand(c), ['PickFromTray', 500]);
    expect(c.view!.hand.pieces, {500: 1});
  });

  testWidgets('an empty slot is dashed and shakes on a tap', (tester) async {
    await pumpTrip(tester);
    final c = controllerOf(tester);
    final empty = find.byKey(Tray.slotKey(20000));
    final full = find.byKey(Tray.slotKey(500));
    Finder dashed(Finder slot) => find.descendant(
      of: slot,
      matching: find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter != null,
      ),
    );
    expect(dashed(empty), findsOneWidget);
    expect(dashed(full), findsNothing);

    final before = c.engine!.commandLog.length;
    final element = tester.element(empty);
    await tester.tap(empty);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(c.engine!.commandLog.length, before, reason: 'nothing applied');
    // The same slot all along: a tap or a drag in progress survives it.
    expect(tester.element(empty), same(element));
    final shaking = find.ancestor(
      of: empty,
      matching: find.byWidgetPredicate(
        (w) => w is Transform && w.transform.getTranslation().x != 0,
      ),
    );
    expect(shaking, findsOneWidget);
    await tester.pumpAndSettle();
    expect(shaking, findsNothing);
    expect(tester.element(empty), same(element));
  });

  testWidgets('a tap on the hand returns it to the drawer', (tester) async {
    await pumpTrip(tester);
    final c = controllerOf(tester);
    final tray = c.view!.tray.firstWhere((s) => s.denomination == 500).count;
    await tester.tap(find.byKey(Tray.slotKey(500)));
    await tester.pump();
    await tester.tap(find.byKey(HandSlot.slotKey));
    await tester.pump();
    expect(lastCommand(c), ['ReturnHand']);
    expect(c.view!.hand.isEmpty, isTrue);
    expect(c.view!.tray.firstWhere((s) => s.denomination == 500).count, tray);
  });

  testWidgets('a tap on a passenger with money in hand throws it', (
    tester,
  ) async {
    await pumpTrip(tester);
    final c = controllerOf(tester);
    await untilAboard(tester, c, 'p1');
    await tester.tap(find.byKey(Tray.slotKey(100)));
    await tester.pump();
    await tester.tap(find.byKey(HitAreas.keyOf('p1')));
    await tester.pump();
    expect(lastCommand(c), ['SendHand', 'p1']);
    expect(c.view!.hand.isEmpty, isTrue);
  });

  testWidgets('with an empty hand, a tap on a passenger asks them', (
    tester,
  ) async {
    await pumpTrip(tester);
    final c = controllerOf(tester);
    await untilAboard(tester, c, 'p1');
    await tester.tap(find.byKey(HitAreas.keyOf('p1')));
    await tester.pump();
    expect(lastCommand(c), ['Tap', 'p1']);
  });

  testWidgets('a drag from the hand onto a passenger throws it too', (
    tester,
  ) async {
    await pumpTrip(tester);
    final c = controllerOf(tester);
    await untilAboard(tester, c, 'p2');
    await tester.tap(find.byKey(Tray.slotKey(100)));
    await tester.pump();
    final from = tester.getCenter(find.byKey(HandSlot.slotKey));
    final to = tester.getCenter(find.byKey(HitAreas.keyOf('p2')));
    final gesture = await tester.startGesture(from);
    for (var i = 1; i <= 10; i++) {
      await gesture.moveTo(Offset.lerp(from, to, i / 10)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pump();
    expect(lastCommand(c), ['SendHand', 'p2']);
  });

  testWidgets('«رجّع» shows only while the throw can be taken back', (
    tester,
  ) async {
    await pumpTrip(tester);
    final c = controllerOf(tester);
    await untilAboard(tester, c, 'p1');
    expect(find.byKey(UndoButton.buttonKey), findsNothing);
    await tester.tap(find.byKey(Tray.slotKey(100)));
    await tester.pump();
    await tester.tap(find.byKey(HitAreas.keyOf('p1')));
    await tester.pump();
    expect(c.view!.undoUntilMs, greaterThan(c.view!.tMs));
    expect(find.byKey(UndoButton.buttonKey), findsOneWidget);

    await tester.tap(find.byKey(UndoButton.buttonKey));
    await tester.pump();
    expect(lastCommand(c), ['UndoLastSend']);

    await tester.tap(find.byKey(Tray.slotKey(100)));
    await tester.pump();
    await tester.tap(find.byKey(HitAreas.keyOf('p1')));
    await tester.pump();
    expect(find.byKey(UndoButton.buttonKey), findsOneWidget);
    advanceMs(c, c.view!.undoUntilMs! - c.view!.tMs + 33);
    await tester.pump();
    expect(find.byKey(UndoButton.buttonKey), findsNothing);
  });

  for (final digits in DigitStyle.values) {
    testWidgets("the hand's total is 20 pt, in ${digits.name} digits", (
      tester,
    ) async {
      await pumpTrip(tester, digits: digits);
      await tester.tap(find.byKey(Tray.slotKey(500)));
      await tester.tap(find.byKey(Tray.slotKey(100)));
      await tester.pump();
      // 008.5 draws it as «= ٦».
      final total = AppLocalizations.of(
        tester.element(find.byKey(HandSlot.slotKey)),
      ).tripHandTotal(NumberFormatter(digits).piasters(600));
      final text = tester.widget<Text>(
        find.descendant(
          of: find.byKey(HandSlot.slotKey),
          matching: find.text(total),
        ),
      );
      expect(text.style!.fontSize, 20);
    });
  }

  testWidgets('«آخر كلام» shows the last two lines', (tester) async {
    await pumpTrip(tester);
    final c = controllerOf(tester);
    for (var i = 0; i < 3000 && c.view!.log.length < 2; i++) {
      advanceMs(c, 33);
    }
    await tester.pump();
    final view = c.view!;
    expect(view.log, hasLength(2));
    final l10n = AppLocalizations.of(tester.element(find.byType(LastWordsLog)));
    final scope = tester
        .element(find.byType(LastWordsLog))
        .getInheritedWidgetOfExactType<TripScope>()!;
    expect(scope.controller, c);
    for (final line in view.log) {
      expect(
        find.descendant(
          of: find.byType(LastWordsLog),
          matching: find.text(
            l10n.logLine(line, const NumberFormatter(DigitStyle.arabicIndic)),
          ),
        ),
        findsOneWidget,
      );
    }
  });
}
