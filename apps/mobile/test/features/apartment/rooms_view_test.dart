// The rooms view (specs/015-m10-apartment-story, contracts/apartment.md "The
// rooms view", T054): the chapter bar, the tabs, the drawing, the grid, the
// strip and the chip that opens a piece.
import 'package:content_models/content_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/economy/economy.dart';
import 'package:wassal/features/apartment/application/apartment_providers.dart';
import 'package:wassal/features/apartment/presentation/room_scene.dart';

import '../../helpers/economy.dart';
import '../../helpers/lines.dart';
import '../../helpers/progress.dart';
import '../../helpers/synthetic_packs.dart';

const _nish = (SkuKind.item, 'salon.nish');
const _sitara = (SkuKind.item, 'salon.sitara');

/// The salon's four pieces: owning them completes chapter 4, which starts the
/// kitchen's chapter.
const _salonDone = {
  _nish,
  _sitara,
  (SkuKind.item, 'salon.antreeh'),
  (SkuKind.item, 'salon.nagfa'),
};

Future<ProviderContainer> _open(
  WidgetTester tester, {
  Set<(SkuKind, String)> owned = const {},
}) async => (await pumpLinesApp(
  tester,
  pack: artboardSalon(),
  location: '/apartment',
  settle: false,
  state: playerState(
    jenehat: 1325,
    stars: hayDone,
    owned: {microOld, shabka, ...owned},
    styles: const {'salon.nish': 'crystal', 'salon.sitara': 'plain'},
  ),
)).$1;

/// The salon finished, the kitchen its own current chapter: two rooms whose
/// chapters have started, so two tabs the player may choose (FR-010).
Future<(ProviderContainer, TestEconomy)> _openTwoRooms(
  WidgetTester tester, {
  int jenehat = 20000,
}) async => pumpLinesApp(
  tester,
  pack: artboardSalonThenKitchen(),
  location: '/apartment',
  settle: false,
  state: playerState(
    jenehat: jenehat,
    stars: hayDone,
    owned: {microOld, shabka, ..._salonDone},
    styles: const {'salon.nish': 'crystal', 'salon.sitara': 'plain'},
  ),
);

void main() {
  testWidgets('the salon, its chapter bar and its four pieces', (tester) async {
    await _open(tester);
    expect(find.text('شقة العُمر'), findsOneWidget);
    expect(find.textContaining('الفصل'), findsOneWidget);
    expect(find.textContaining('جهّزت'), findsOneWidget);
    expect(find.text('الصالة'), findsOneWidget);
    expect(find.byType(RoomScene), findsOneWidget);
    // The four pieces: two installed, two missing.
    expect(find.text('النيش'), findsWidgets);
    expect(find.text('الستارة'), findsWidgets);
    expect(find.text('الأنتريه'), findsWidgets);
    expect(find.text('النجفة'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('owned pieces read «اتركّبت», the others their shortfall and '
      'price', (tester) async {
    await _open(tester, owned: {_nish, _sitara});
    expect(find.text('اتركّبت'), findsNWidgets(2));
    // 3,200 at a 1,325 balance: 1,875 short.
    expect(find.textContaining('ناقصك'), findsOneWidget);
    expect(find.textContaining('٢٬٤٠٠'), findsWidgets);
  });

  testWidgets('a missing piece opens its sheet route', (tester) async {
    final container = await _open(tester);
    await tester.tap(find.textContaining('النجفة').last);
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
    expect(locationOf(container), contains('/apartment/item/'));
  });

  // R3-1 (FR-010, FR-015): a tab tap used to move only the highlight. The
  // view opens on the current chapter's room and a started room's tab shows
  // that room: its drawing, its grid and its chapter bar, with a crossfade.
  testWidgets('a tab tap shows that room: the scene, the grid and the bar', (
    tester,
  ) async {
    final (container, _) = await _openTwoRooms(tester);
    // The current chapter's room: the kitchen.
    expect(find.textContaining('· المطبخ'), findsOneWidget);
    expect(find.text('البوتاجاز'), findsWidgets);
    expect(find.text('النيش'), findsNothing);
    expect(find.text('شوف المشهد'), findsNothing);

    await tester.tap(find.text('الصالة'));
    await tester.pump();
    // Both drawings are up while the old one fades (at most 150 ms).
    expect(find.byType(RoomScene), findsNWidgets(2));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(RoomScene), findsOneWidget);

    // The salon: its chapter bar, its pieces, and the scene it waits on.
    expect(find.textContaining('· الصالون'), findsOneWidget);
    expect(find.text('النيش'), findsWidgets);
    expect(find.text('البوتاجاز'), findsNothing);
    expect(find.text('شوف المشهد'), findsOneWidget);
    expect(container.read(roomTabIdProvider), RoomId.salon);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a new chapter forgets the chosen room', (tester) async {
    final (container, economy) = await _openTwoRooms(tester);
    await tester.tap(find.text('الصالة'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(container.read(roomTabIdProvider), RoomId.salon);

    // The kitchen's only piece completes chapter 5: the story moves on to 6.
    final bought = await economy.service.buy(
      economy.service.newRequestId(),
      kind: SkuKind.item,
      skuId: 'kitchen.stove',
      variantId: 'classic',
    );
    expect(bought, isA<OpApplied>());
    await tester.pump(const Duration(milliseconds: 200));

    expect(container.read(roomTabIdProvider), isNull);
    // The view is on the current chapter's room again, the kitchen finished.
    expect(find.textContaining('· المطبخ'), findsOneWidget);
    expect(find.text('اتركّبت'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
