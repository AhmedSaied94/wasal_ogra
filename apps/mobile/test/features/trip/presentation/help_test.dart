import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/core/l10n/number_formatter.dart';
import 'package:flame/game.dart';
import 'package:wassal/features/trip/application/trip_controller.dart';
import 'package:wassal/features/trip/domain/scene_layout.dart';
import 'package:wassal/features/trip/domain/trip_facts.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';
import 'package:wassal/features/trip/presentation/cards/booster_card.dart';
import 'package:wassal/features/trip/presentation/cards/pause_card.dart';
import 'package:wassal/features/trip/presentation/dashboard/boosters_row.dart';
import 'package:wassal/features/trip/presentation/dashboard/hand_slot.dart';
import 'package:wassal/features/trip/presentation/dashboard/tray.dart';
import 'package:wassal/features/trip/presentation/overlays/choices_layer.dart';
import 'package:wassal/features/trip/presentation/scene/trip_game.dart';
import 'package:wassal/features/trip/presentation/overlays/hint_layer.dart';
import 'package:wassal/features/trip/presentation/top_bar/top_bar.dart';

import '../../../helpers/economy.dart';
import '../../../helpers/trip.dart';

// The help on screen: boosters and their purchase card, «حد معاه فكة؟»,
// the ledger's badges, بلية's hints, and the rejections (tasks.md T076).

const _numbers = NumberFormatter(DigitStyle.arabicIndic);

int priceOf(BoosterId booster) =>
    sampleContent().price(SkuKind.booster, switch (booster) {
      BoosterId.changeBag => 'change_bag',
      BoosterId.wakeAll => 'wake_all',
      BoosterId.ledgerPeek => 'ledger_peek',
      _ => 'traffic_jam',
    })!.amount;

Finder inSlot(BoosterId booster, String text) => find.descendant(
  of: find.byKey(BoostersRow.slotKey(booster)),
  matching: find.text(text),
);

Future<TripController> open(
  WidgetTester tester, {
  required TestEconomy economy,
  String tripId = 'line_hay.01',
}) async {
  await pumpTrip(tester, tripId: tripId, economy: economy);
  final c = controllerOf(tester);
  advanceMs(c, 1000);
  await tester.pump();
  return c;
}

void main() {
  testWidgets('the boosters show their count, or their price when none is '
      'left', (tester) async {
    await open(
      tester,
      economy: await stockedEconomy(stock: {BoosterId.changeBag: 2}),
    );
    expect(inSlot(BoosterId.changeBag, _numbers.integer(2)), findsOneWidget);
    for (final booster in [
      BoosterId.wakeAll,
      BoosterId.ledgerPeek,
      BoosterId.trafficJam,
    ]) {
      expect(
        inSlot(booster, _numbers.integer(priceOf(booster))),
        findsOneWidget,
        reason: booster.name,
      );
    }
    for (final booster in tripBoosters) {
      final size = tester.getSize(find.byKey(BoostersRow.slotKey(booster)));
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
    }
  });

  testWidgets('a tap uses one', (tester) async {
    final economy = await stockedEconomy(stock: {BoosterId.changeBag: 2});
    final c = await open(tester, economy: economy);
    await tester.tap(find.byKey(BoostersRow.slotKey(BoosterId.changeBag)));
    await tester.pumpAndSettle();
    expect(c.engine!.state.boostersUsed, [BoosterId.changeBag]);
    expect(inSlot(BoosterId.changeBag, _numbers.integer(1)), findsOneWidget);
  });

  testWidgets('the ledger\'s badges show only while it is open', (
    tester,
  ) async {
    final economy = await stockedEconomy(stock: {BoosterId.ledgerPeek: 1});
    final c = await open(tester, economy: economy);
    expect(find.byType(LedgerBadgeChip), findsNothing);

    await tester.tap(find.byKey(BoostersRow.slotKey(BoosterId.ledgerPeek)));
    await tester.pumpAndSettle();
    final aboard = [
      for (final p in c.view!.passengers)
        if (p.ledgerBadge != null) p,
    ];
    expect(aboard, isNotEmpty);
    for (final p in aboard) {
      final badge = find.byKey(LedgerBadgeChip.badgeKey(p.passengerId));
      expect(badge, findsOneWidget);
      expect(
        find.descendant(
          of: badge,
          matching: find.text(
            p.ledgerBadge == LedgerBadge.paid ? 'دافع' : 'لسه',
          ),
        ),
        findsOneWidget,
      );
    }

    advanceMs(c, bundledParams(LineId.lineHay).boosterLedgerPeekMs + 33);
    await tester.pump();
    expect(find.byType(LedgerBadgeChip), findsNothing);
  });

  group('the purchase card', () {
    testWidgets('shows the price and the balance, and buys', (tester) async {
      final economy = await stockedEconomy(bonat: 50);
      final c = await open(tester, economy: economy);
      await tester.tap(find.byKey(BoostersRow.slotKey(BoosterId.changeBag)));
      await tester.pumpAndSettle();
      expect(find.byType(BoosterCard), findsOneWidget);
      final price = _numbers.integer(priceOf(BoosterId.changeBag));
      expect(find.text('بـ$price بونات'), findsOneWidget);
      expect(find.text('معاك ${_numbers.integer(50)} بونات'), findsOneWidget);

      await tester.tap(find.byKey(BoosterCard.buyKey));
      await tester.pumpAndSettle();
      expect(find.byType(BoosterCard), findsNothing);
      expect(c.engine!.state.boostersUsed, [BoosterId.changeBag]);
      expect(economy.service.view.bonat, 50 - priceOf(BoosterId.changeBag));
    });

    testWidgets('says how much is missing', (tester) async {
      final economy = await stockedEconomy(bonat: 3);
      await open(tester, economy: economy);
      await tester.tap(find.byKey(BoostersRow.slotKey(BoosterId.changeBag)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(BoosterCard.buyKey));
      await tester.pumpAndSettle();
      final missing = _numbers.integer(priceOf(BoosterId.changeBag) - 3);
      expect(find.text('ناقصك $missing بونات'), findsOneWidget);
      expect(find.byKey(BoosterCard.buyKey), findsNothing);

      await tester.tap(find.byKey(BoosterCard.closeKey));
      await tester.pumpAndSettle();
      expect(find.byType(BoosterCard), findsNothing);
    });
  });

  group('«حد معاه فكة؟»', () {
    testWidgets('lights the notes, and a tap on one breaks it', (tester) async {
      final c = await open(
        tester,
        economy: await testEconomy(),
        tripId: 'line_gamaa.02',
      );
      final button = find.byKey(BreakButton.buttonKey);
      expect(button, findsOneWidget);
      expect(
        find.descendant(of: button, matching: find.text('حد معاه فكة؟')),
        findsOneWidget,
      );
      final left = c.view!.breakButton.left;
      expect(
        find.descendant(
          of: button,
          matching: find.text(_numbers.integer(left)),
        ),
        findsOneWidget,
      );

      await tester.tap(button);
      await tester.pump();
      expect(c.view!.breakMode, isTrue);
      await tester.tap(find.byKey(Tray.slotKey(1000)));
      await tester.pump();
      expect(c.engine!.commandLog.last.toJson().sublist(1), [
        'RequestBreak',
        1000,
      ]);
      expect(c.view!.breakMode, isFalse);
      expect(
        find.descendant(
          of: button,
          matching: find.text(_numbers.integer(left - 1)),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a second tap on it cancels', (tester) async {
      final c = await open(
        tester,
        economy: await testEconomy(),
        tripId: 'line_gamaa.02',
      );
      await tester.tap(find.byKey(BreakButton.buttonKey));
      await tester.pump();
      await tester.tap(find.byKey(BreakButton.buttonKey));
      await tester.pump();
      expect(c.view!.breakMode, isFalse);
    });

    testWidgets('with none left, says so in the log\'s place for 2 s', (
      tester,
    ) async {
      final c = await open(
        tester,
        economy: await testEconomy(),
        tripId: 'line_gamaa.02',
      );
      for (final note in [1000, 2000]) {
        c
          ..startBreak()
          ..pickBreak(note);
      }
      await tester.pump();
      await tester.tap(find.byKey(BreakButton.buttonKey));
      await tester.pump();
      expect(find.text('خلصت مرات الفكة في المشوار ده'), findsOneWidget);
      advanceMs(c, 2000 + 33);
      await tester.pump();
      expect(find.text('خلصت مرات الفكة في المشوار ده'), findsNothing);
    });
  });

  testWidgets('بلية points at whom his hint is about', (tester) async {
    final fixture = loadFixture('sample__line_gamaa_01_three_stars');
    await pumpTrip(
      tester,
      tripId: fixture.definition.tripId,
      fixed: FixedTrip(
        definition: fixture.definition,
        params: fixture.params,
        seed: fixture.seed,
      ),
    );
    final c = controllerOf(tester);
    final hint = c.view!.hint;
    expect(hint, isNotNull);
    expect(find.byKey(HintLayer.headKey), findsOneWidget);
    expect(find.byKey(HintLayer.bubbleKey), findsOneWidget);
    final target = hint!.targetPassengerId!;
    final pointer = tester.getRect(find.byKey(HintLayer.pointerKey));
    final scene = tester.getRect(find.byType(GameWidget<TripGame>));
    final face = SceneLayout(
      c.session!.facts.definition.seats,
      width: scene.width,
      height: scene.height,
    ).seats[c.view!.passenger(target)!.seatId]!.face;
    final faceRect = Rect.fromLTWH(
      scene.left + face.left,
      scene.top + face.top,
      face.width,
      face.height,
    );
    expect(pointer.overlaps(faceRect.inflate(24)), isTrue);
  });

  testWidgets('at the command limit only pause still answers', (tester) async {
    final c = await open(tester, economy: await testEconomy());
    while (!c.view!.controlsLocked) {
      c
        ..pick(50)
        ..returnHand();
    }
    await tester.pump();
    final commands = c.engine!.commandLog.length;
    await tester.tap(find.byKey(Tray.slotKey(100)));
    await tester.tap(find.byKey(BreakButton.buttonKey));
    await tester.tap(find.byKey(BoostersRow.slotKey(BoosterId.changeBag)));
    await tester.pumpAndSettle();
    expect(c.engine!.commandLog, hasLength(commands));
    expect(c.view!.breakMode, isFalse);
    expect(c.phase, TripPhase.running);

    await tester.tap(find.byKey(TripTopBar.pauseKey));
    await tester.pumpAndSettle();
    expect(find.byType(PauseCard), findsOneWidget);
  });
}
