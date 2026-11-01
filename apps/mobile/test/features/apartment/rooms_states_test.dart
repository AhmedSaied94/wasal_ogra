// The apartment's boards of 2026-10-31 as behaviour (specs/015-m10-apartment-
// story, T131): سلمى's bubble after a purchase and where it ends, the
// finished room's scene chip, a locked tab that takes no tap, the pending
// chip, and the piece sheet's request mark and CTA. The boxes and the pictures
// are `test/design/apt_states_layout_test.dart` and the goldens beside it.
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/features/apartment/application/apartment_providers.dart';
import 'package:wassal/features/apartment/presentation/chapter_bar.dart';
import 'package:wassal/features/apartment/presentation/pending_chip.dart';
import 'package:wassal/features/apartment/presentation/piece_sheet.dart';
import 'package:wassal/features/apartment/presentation/room_done_dialog.dart';
import 'package:wassal/features/apartment/presentation/goal_headline.dart';

import '../../design/samples/apt_states.dart';
import '../../helpers/lines.dart';

void main() {
  group('after a purchase (AptRoomsBought)', () {
    testWidgets('سلمى comments under the new piece, and a tap ends it', (
      tester,
    ) async {
      final container = await pumpAptRoomsBought(tester);
      expect(find.byKey(const ValueKey('RoomScene.bubble')), findsOneWidget);
      expect(find.textContaining('الكريستال بيلمع في النور'), findsOneWidget);
      expect(container.read(boughtPieceProvider)?.itemId, 'salon.nagafa');

      // Anywhere on the rooms view.
      await tester.tapAt(const Offset(200, 20));
      await tester.pump(const Duration(milliseconds: 50));
      expect(container.read(boughtPieceProvider), isNull);
      expect(find.byKey(const ValueKey('RoomScene.bubble')), findsNothing);
    });

    testWidgets('a scroll ends it as well', (tester) async {
      final container = await pumpAptRoomsBought(tester);
      expect(container.read(boughtPieceProvider), isNotNull);
      await tester.drag(find.byType(ListView).first, const Offset(0, -60));
      await tester.pump(const Duration(milliseconds: 50));
      expect(container.read(boughtPieceProvider), isNull);
    });

    testWidgets('the room is announced once, politely', (tester) async {
      final calls = <Object?>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockDecodedMessageHandler<Object?>(SystemChannels.accessibility, (
            message,
          ) async {
            calls.add(message);
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockDecodedMessageHandler<Object?>(
              SystemChannels.accessibility,
              null,
            ),
      );
      await pumpAptRoomsBought(tester);
      expect(calls.toString(), contains('اشتريت النجفة'));
    });
  });

  group('the finished room (AptRoomsDone)', () {
    testWidgets('«شوف المشهد» is a control of its own inside the bar', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final container = await pumpAptRoomsDone(tester);
      final chip = find.bySemanticsLabel('شوف المشهد: العيلة في الصالون');
      expect(chip, findsOneWidget);
      // The bar still opens the timeline, by its own label.
      expect(find.bySemanticsLabel(RegExp('خلصت، كل الفصول')), findsOneWidget);
      await tester.tap(chip);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(locationOf(container), startsWith('/story/scene/'));
      semantics.dispose();
    });

    testWidgets('the end of the story closes the strip with the end line', (
      tester,
    ) async {
      await pumpAptRoomsDone(tester);
      expect(find.text('باقي الحكاية جاية في تحديث قريب'), findsOneWidget);
    });
  });

  group('the tabs (AptRoomsAffordable)', () {
    testWidgets('a locked room is inert and reads «مقفولة»', (tester) async {
      final semantics = tester.ensureSemantics();
      final container = await pumpAptRoomsAffordable(tester);
      final kitchen = find.bySemanticsLabel('المطبخ، مقفولة');
      expect(kitchen, findsOneWidget);
      final data = tester.getSemantics(kitchen).getSemanticsData();
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.hasAction(SemanticsAction.tap), isFalse);
      final before = locationOf(container);
      await tester.tap(find.text('المطبخ'), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 100));
      expect(locationOf(container), before);
      semantics.dispose();
    });

    testWidgets('the pending chip: «+٥ بون» over «في الطريق»', (tester) async {
      await pumpAptRoomsAffordable(tester);
      expect(find.byType(PendingChip), findsOneWidget);
      expect(find.textContaining('بون'), findsWidgets);
      expect(find.text('في الطريق'), findsOneWidget);
    });

    testWidgets('no chip while nothing is pending', (tester) async {
      await pumpAptRoomsDone(tester);
      expect(find.text('في الطريق'), findsNothing);
    });

    testWidgets('the bar opens the timeline', (tester) async {
      final container = await pumpAptRoomsAffordable(tester);
      await tester.tap(find.byType(ChapterBar));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(locationOf(container), '/apartment/chapters');
    });
  });

  group('the piece sheet (PieceAffordable)', () {
    testWidgets('the request hangs off its style; no «تقدر تشتريها» line', (
      tester,
    ) async {
      await pumpPieceAffordable(tester);
      expect(find.text('طلب أم العروسة'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(PieceSheet),
          matching: find.text('تقدر تشتريها'),
        ),
        findsNothing,
      );
      expect(find.text('لو اخترت ده، طلب أم العروسة هيفوتك'), findsOneWidget);
      expect(find.byKey(PieceSheet.buyKey), findsOneWidget);
    });

    testWidgets('the CTA carries the price taken on a sun chip', (
      tester,
    ) async {
      await pumpPieceAffordable(tester);
      expect(find.textContaining('−'), findsOneWidget);
    });
  });

  group('the finished room dialog (RoomDonePending)', () {
    testWidgets('«+٤٥ بون مكافأة», «في الطريق», the scene and «بعدين»', (
      tester,
    ) async {
      await pumpRoomDonePending(tester);
      expect(find.byType(RoomDoneDialog), findsOneWidget);
      expect(find.textContaining('مكافأة'), findsOneWidget);
      expect(find.text('في الطريق'), findsWidgets);
      expect(find.byKey(RoomDoneDialog.ctaKey), findsOneWidget);
      expect(find.byKey(RoomDoneDialog.laterKey), findsOneWidget);
    });
  });

  group('the goal headline (AptGoalVehicle)', () {
    Future<Size> sizeAt(WidgetTester tester, double width) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.rtl,
          child: Center(
            child: SizedBox(
              width: width,
              child: GoalHeadline(
                name: const SizedBox(width: 120, height: 20),
                figures: const SizedBox(width: 80, height: 16),
              ),
            ),
          ),
        ),
      );
      return tester.getSize(find.byType(GoalHeadline));
    }

    testWidgets('one row when name and figures fit, two when they do not', (
      tester,
    ) async {
      expect((await sizeAt(tester, 300)).height, 20);
      expect((await sizeAt(tester, 200)).height, 20 + 2 + 16);
    });

    testWidgets('the figures sit at the end side on their own row', (
      tester,
    ) async {
      await sizeAt(tester, 200);
      final name = tester.getTopRight(find.byType(SizedBox).at(1));
      final figures = tester.getTopLeft(find.byType(SizedBox).at(2));
      expect(figures.dy, greaterThan(name.dy));
    });
  });
}
