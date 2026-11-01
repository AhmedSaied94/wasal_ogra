// The piece sheet (specs/015-m10-apartment-story, contracts/apartment.md
// "The piece sheet", T055): its styles, the mark, the lines, the price and
// the two buttons.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/features/apartment/presentation/piece_sheet.dart';

import '../../helpers/lines.dart';
import '../../helpers/progress.dart';
import '../../helpers/synthetic_packs.dart';

Future<ProviderContainer> _open(
  WidgetTester tester, {
  String itemId = 'salon.nagfa',
  int jenehat = 1325,
}) async => (await pumpLinesApp(
  tester,
  pack: artboardSalon(),
  location: '/apartment/item/$itemId',
  settle: false,
  state: playerState(
    jenehat: jenehat,
    stars: hayDone,
    owned: {microOld, shabka},
  ),
)).$1;

void main() {
  testWidgets('the sheet: its room, name, styles and the family\'s mark', (
    tester,
  ) async {
    await _open(tester);
    expect(find.text('الصالة'), findsWidgets);
    expect(find.text('النجفة'), findsWidgets);
    expect(find.text('كريستال'), findsWidgets);
    expect(find.text('كلاسيك'), findsWidgets);
    // The نجفة's crystal is the bride's father's request.
    expect(find.textContaining('طلب أبو العروسة'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('short: «ناقصك» and «اطلع مشوار»', (tester) async {
    await _open(tester);
    // 2,400 with 1,325: 1,075 short.
    expect(find.textContaining('ناقصك'), findsWidgets);
    expect(find.byKey(PieceSheet.goKey), findsOneWidget);
    expect(find.byKey(PieceSheet.buyKey), findsNothing);
  });

  testWidgets('affordable: «اشتري» spends once and closes', (tester) async {
    final container = await _open(tester, jenehat: 2400);
    expect(find.byKey(PieceSheet.buyKey), findsOneWidget);
    await tester.tap(find.byKey(PieceSheet.buyKey));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
    expect(locationOf(container), contains('/apartment'));
  });

  testWidgets('an unknown or owned piece goes back to the tab', (tester) async {
    final container = await _open(tester, itemId: 'salon.nope');
    await tester.pump(const Duration(milliseconds: 400));
    expect(locationOf(container), '/apartment');
  });
}
