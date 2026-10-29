// Lines (specs/014-m09-lines-vehicles, contracts/lines.md, US1, US4): the
// header, every tile and card, where each tap goes, «كمّل» against the
// card, the focus scroll, offline, a sync redraw, and a long map.
import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/economy/economy_providers.dart';
import 'package:wassal/core/routing/router.dart';
import 'package:wassal/core/sync/server_status.dart';
import 'package:wassal/features/lines/presentation/line_card.dart';
import 'package:wassal/features/lines/presentation/line_map.dart';
import 'package:wassal/features/lines/presentation/lines_screen.dart';
import 'package:wassal/features/lines/presentation/vehicle_strip.dart';
import 'package:wassal/features/pre_trip/presentation/pre_trip_card.dart';

import '../../helpers/home.dart';
import '../../helpers/lines.dart';
import '../../helpers/surfaces.dart';
import '../../design/samples/lines.dart';

/// The `Lines` board's player: the micro_old, خط الحي done at 54 of 60,
/// خط الجامعة at trip 12.
final _board = boardPlayer();

void main() {
  testWidgets('the header: coins without a tap, BONAT to the shop', (
    tester,
  ) async {
    final (container, _) = await pumpLinesApp(tester, state: _board);
    expect(find.byType(LinesScreen), findsOneWidget);
    expect(labelled('الجنيهات ١٬٢٤٠'), findsOneWidget);
    await tester.tap(find.byKey(LinesScreen.coinsKey));
    await tester.pumpAndSettle();
    expect(locationOf(container), '/lines');
    await tester.tap(find.byKey(LinesScreen.bonatKey));
    await tester.pumpAndSettle();
    expect(locationOf(container), '/shop');
  });

  testWidgets('offline, BONAT is no link and says so', (tester) async {
    final (container, _) = await pumpLinesApp(
      tester,
      state: _board,
      serverStatus: const ServerStatusState(reach: Reach.offline),
    );
    expect(labelled('البونات ٨٥، المحل محتاج نت'), findsOneWidget);
    await tester.tap(find.byKey(LinesScreen.bonatKey));
    await tester.pumpAndSettle();
    expect(locationOf(container), '/lines');
  });

  testWidgets('every tile state, each opening its sheet', (tester) async {
    final (container, _) = await pumpLinesApp(tester, state: _board);
    expect(labelled('توكتوك المعلم، خلصته'), findsOneWidget);
    expect(labelled('ميكروباص قديم، عربيتك دلوقتي'), findsOneWidget);
    expect(labelled('ميكروباص جديد، بـ٥٬٠٠٠ جنيه'), findsOneWidget);
    expect(labelled('ميكروباص سفر، مقفولة'), findsOneWidget);
    expect(find.text('قديم · عربيتك'), findsOneWidget);
    await tester.tap(find.byKey(VehicleTileView.keyOf(VehicleId.microNew)));
    await tester.pumpAndSettle();
    expect(locationOf(container), '/lines/vehicle/micro_new');
  });

  testWidgets('every card state and where its tap goes', (tester) async {
    final (container, _) = await pumpLinesApp(tester, state: _board);
    // Done: خلص, its stars and «عيد عشان النجوم» unless all three.
    expect(find.text('خلص'), findsOneWidget);
    expect(shows('٥٤/٦٠ · عيد عشان النجوم'), findsOneWidget);
    // Current: what's new, the star line, «كمّل».
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Text &&
            (w.data
                    ?.replaceAll(RegExp('[\u2066-\u2069]'), '')
                    .contains('المشوار ١٢ من ٣٠') ??
                false),
      ),
      findsOneWidget,
    );
    expect(shows('٨٫٥ ج'), findsOneWidget);
    expect(
      labelled('خط الجامعة، الحالي، ٢٥ من ٩٠ نجمة، المشوار ١٢ من ٣٠'),
      findsOneWidget,
    );
    // Locked, with its reason and what's new.
    expect(find.text('محتاج ميكروباص جديد · الشنط والمتهرب'), findsOneWidget);
    expect(find.text('بعد خط السوق · زحمة الصيف'), findsOneWidget);

    for (final (line, want) in [
      (LineId.lineGamaa, '/lines/line_gamaa'),
      (LineId.lineHay, '/lines/line_hay'),
      // A line behind a vehicle opens that vehicle's sheet; behind a line,
      // its locked details (US4).
      (LineId.lineSouq, '/lines/vehicle/micro_new'),
      (LineId.lineMasyaf, '/lines/line_masyaf'),
      (LineId.lineSafar, '/lines/vehicle/micro_safar'),
    ]) {
      final card = find.byKey(LineCard.keyOf(line));
      await tester.ensureVisible(card);
      await tester.pumpAndSettle();
      await tester.tapAt(tester.getTopLeft(card) + const Offset(40, 20));
      await tester.pumpAndSettle();
      expect(locationOf(container), want, reason: line.name);
      container.read(routerProvider).go('/lines');
      await tester.pumpAndSettle();
    }
  });

  testWidgets('«كمّل» is its own button, after its card, 63×44', (
    tester,
  ) async {
    final (container, _) = await pumpLinesApp(tester, state: _board);
    final go = find.byKey(LineCard.continueKeyOf(LineId.lineGamaa));
    expect(go, findsOneWidget);
    expect(labelled('كمّل المشوار ١٢'), findsOneWidget);
    final size = tester.getSize(go);
    expect(size.width, greaterThanOrEqualTo(LineCard.continueSize.width));
    expect(size.height, greaterThanOrEqualTo(44));
    await tester.tap(go);
    await tester.pumpAndSettle();
    // The card opens under the line's details, so its close lands there.
    expect(locationOf(container), '/lines/line_gamaa/pre-trip/line_gamaa.12');
    expect(find.byType(PreTripCard), findsOneWidget);
    await tester.tap(find.byKey(PreTripCard.closeKey));
    await tester.pumpAndSettle();
    expect(locationOf(container), '/lines/line_gamaa');
  });

  testWidgets('the cards read top to bottom: the last line first', (
    tester,
  ) async {
    await pumpLinesApp(tester, state: _board);
    final safar = tester.getTopLeft(
      find.byKey(LineCard.keyOf(LineId.lineSafar)),
    );
    final hay = tester.getTopLeft(find.byKey(LineCard.keyOf(LineId.lineHay)));
    expect(safar.dy, lessThan(hay.dy));
  });

  testWidgets('the focus card is in view on the first frame', (tester) async {
    // A new player: Home's next trip is on خط الحي, at the map's bottom.
    await pumpLinesApp(tester, surface: Surface.small, textScale: 1.3);
    final hay = find.byKey(LineCard.keyOf(LineId.lineHay));
    final map = tester.getRect(find.byKey(LineMap.scrollKey));
    final card = tester.getRect(hay);
    expect(map.overlaps(card), isTrue);
  });

  testWidgets('five lines at 1.3 scroll', (tester) async {
    await pumpLinesApp(
      tester,
      state: _board,
      surface: Surface.small,
      textScale: 1.3,
    );
    final scroll = tester.state<ScrollableState>(
      find.descendant(
        of: find.byKey(LineMap.scrollKey),
        matching: find.byType(Scrollable),
      ),
    );
    expect(scroll.position.maxScrollExtent, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a balance or progress change redraws without reopening', (
    tester,
  ) async {
    final (container, economy) = await pumpLinesApp(
      tester,
      state: playerState(jenehat: 1600),
    );
    expect(labelled('ميكروباص قديم، بـ١٬٥٠٠ جنيه'), findsOneWidget);
    await economy.service.buy(
      economy.service.newRequestId(),
      kind: SkuKind.vehicle,
      skuId: 'micro_old',
    );
    await tester.pumpAndSettle();
    expect(labelled('ميكروباص قديم، عربيتك دلوقتي'), findsOneWidget);
    expect(container.read(economyViewProvider).jenehat, 100);
    expect(
      find.byKey(LineCard.continueKeyOf(LineId.lineGamaa)),
      findsOneWidget,
    );
  });
}
