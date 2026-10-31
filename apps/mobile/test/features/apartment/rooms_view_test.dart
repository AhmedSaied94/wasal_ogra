// The rooms view (specs/015-m10-apartment-story, contracts/apartment.md "The
// rooms view", T054): the chapter bar, the tabs, the drawing, the grid, the
// strip and the chip that opens a piece.
import 'package:content_models/content_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/features/apartment/presentation/room_scene.dart';

import '../../helpers/lines.dart';
import '../../helpers/progress.dart';
import '../../helpers/synthetic_packs.dart';

const _nish = (SkuKind.item, 'salon.nish');
const _sitara = (SkuKind.item, 'salon.sitara');

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
}
