// RoomDone (specs/015-m10-apartment-story, contracts/apartment.md
// "RoomDone", T067): the finished room, its reward on its way, and what the
// two buttons do.
import 'package:content_models/content_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/routing/router.dart';
import 'package:wassal/features/apartment/presentation/piece_sheet.dart';
import 'package:wassal/features/apartment/presentation/room_done_dialog.dart';
import 'package:wassal/features/story/presentation/scene_viewer_page.dart';

import '../../helpers/lines.dart';
import '../../helpers/progress.dart';
import '../../helpers/synthetic_packs.dart';

/// Three of the salon's four pieces owned; the sheet opens the fourth.
Future<ProviderContainer> _open(
  WidgetTester tester, {
  Map<String, Object?>? pack,
}) async {
  final all = [
    for (final item in artboardSalonContent().itemsOf(RoomId.salon))
      item.itemId,
  ];
  return (await pumpLinesApp(
    tester,
    pack: pack ?? artboardSalon(),
    location: '/apartment/item/${all.last}',
    settle: false,
    state: playerState(
      jenehat: 5000,
      stars: hayDone,
      owned: {
        microOld,
        shabka,
        for (final id in all.take(3)) (SkuKind.item, id),
      },
      styles: const {
        'salon.nish': 'classic',
        'salon.sitara': 'plain',
        'salon.antreeh': 'classic',
      },
    ),
  )).$1;
}

Future<void> _buyAndSettle(WidgetTester tester) async {
  await tester.tap(find.byKey(PieceSheet.buyKey));
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('the last piece opens RoomDone with both rewards', (
    tester,
  ) async {
    final container = await _open(tester);
    await _buyAndSettle(tester);
    expect(find.byType(RoomDoneDialog), findsOneWidget);
    expect(find.textContaining('خلصت'), findsWidgets);
    // The salon's 20 plus chapter 4's 15.
    expect(find.textContaining('مكافأة'), findsOneWidget);
    // The scene it opens is the chapter's goal scene.
    expect(find.byKey(RoomDoneDialog.ctaKey), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(locationOf(container), contains('/apartment/item/'));
  });

  testWidgets('«شوف المشهد» plays the goal scene and comes back to the '
      'apartment', (tester) async {
    final container = await _open(tester);
    await _buyAndSettle(tester);
    final router = container.read(routerProvider);
    await tester.tap(find.byKey(RoomDoneDialog.ctaKey));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    // The scene replaced the sheet. The router's `state` is the top page's;
    // `locationOf` leaves pushed pages out.
    expect(router.state.uri.path, '/story/scene/family_visit');
    expect(find.byType(SceneViewerPage), findsOneWidget);
    expect(find.byType(PieceSheet), findsNothing);

    for (
      var i = 0;
      i < 12 && find.byKey(SceneViewerPage.continueKey).evaluate().isEmpty;
      i++
    ) {
      await tester.tap(find.byKey(SceneViewerPage.panelKey));
      await tester.pump(const Duration(milliseconds: 600));
    }
    await tester.tap(find.byKey(SceneViewerPage.continueKey));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(router.state.uri.path, '/apartment');
    expect(find.byType(SceneViewerPage), findsNothing);
  });

  testWidgets('the room finished is the one drawn, even when the kitchen is '
      'the next chapter\'s room', (tester) async {
    final container = await _open(tester, pack: artboardSalonThenKitchen());
    await _buyAndSettle(tester);
    final dialog = find.byType(RoomDoneDialog);
    expect(dialog, findsOneWidget);
    // The salon (الصالة) and its scene, never the kitchen the story moved on
    // to.
    expect(
      find.descendant(of: dialog, matching: find.textContaining('الصالة')),
      findsWidgets,
    );
    expect(
      find.descendant(of: dialog, matching: find.textContaining('المطبخ')),
      findsNothing,
    );
    expect(find.byKey(RoomDoneDialog.ctaKey), findsOneWidget);
    await tester.tap(find.byKey(RoomDoneDialog.ctaKey));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(
      container.read(routerProvider).state.uri.path,
      '/story/scene/family_visit',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('«بعدين» closes and the scene stays waiting', (tester) async {
    final container = await _open(tester);
    await _buyAndSettle(tester);
    await tester.tap(find.byKey(RoomDoneDialog.laterKey));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(RoomDoneDialog), findsNothing);
    expect(locationOf(container), '/apartment');
    // The rooms view shows the finished salon: four pieces installed.
    expect(find.text('اتركّبت'), findsNWidgets(4));
  });

  testWidgets('a purchase that leaves the room short opens no dialog', (
    tester,
  ) async {
    final all = [
      for (final item in artboardSalonContent().itemsOf(RoomId.salon))
        item.itemId,
    ];
    await pumpLinesApp(
      tester,
      pack: artboardSalon(),
      location: '/apartment/item/${all.first}',
      settle: false,
      state: playerState(
        jenehat: 5000,
        stars: hayDone,
        owned: {microOld, shabka},
      ),
    );
    await _buyAndSettle(tester);
    expect(find.byType(RoomDoneDialog), findsNothing);
  });
}
