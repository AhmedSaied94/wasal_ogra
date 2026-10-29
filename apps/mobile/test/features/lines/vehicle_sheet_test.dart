// A vehicle's sheet (specs/014-m09-lines-vehicles, contracts/buy-vehicle.md,
// US3, US4): the affordable and short offers, each outcome of «اشتريها»,
// a sync that flips short and affordable, a rollback, closing with nothing
// spent, the owned and not-for-sale sheets, and an id the pack lacks.
import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/economy/economy_providers.dart';
import 'package:wassal/core/theme/components/overlays.dart';
import 'package:wassal/features/lines/presentation/vehicle_sheet.dart';

import '../../helpers/economy.dart';
import '../../helpers/home.dart';
import '../../helpers/lines.dart';
import '../../helpers/progress.dart';
import '../../helpers/routing.dart';
import '../../helpers/synthetic_packs.dart';

void main() {
  testWidgets('affordable: the facts, the price card, the impact and two '
      'buttons', (tester) async {
    final (container, _) = await pumpLinesApp(
      tester,
      pack: draftShaped(),
      state: playerState(
        jenehat: 4000,
        stars: {
          for (var n = 1; n <= 19; n++)
            'line_hay.${n.toString().padLeft(2, '0')}': 1,
        },
      ),
      location: '/lines/vehicle/micro_old',
    );
    expect(find.byType(VehicleSheet), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(VehicleSheet),
        matching: shows('الميكروباص القديم'),
      ),
      findsOneWidget,
    );
    // Ten takes the few form: «كراسي».
    expect(labelled('١٠ كراسي بدل ٣'), findsOneWidget);
    expect(labelled('بيفتح خط الجامعة'), findsOneWidget);
    expect(labelled('قبض أكتر في كل مشوار'), findsOneWidget);
    expect(labelled('السعر ٣٬٢٠٠ جنيه، معاك ٤٬٠٠٠ جنيه'), findsOneWidget);
    expect(shows('بعد الشرا، فاضل ٥٬٢٠٠ ج على الشبكة'), findsOneWidget);
    expect(find.byKey(VehicleSheet.buyKey), findsOneWidget);
    expect(find.byKey(VehicleSheet.laterKey), findsOneWidget);
    expect(find.byKey(VehicleSheet.shortfallKey), findsNothing);
    expect(locationOf(container), '/lines/vehicle/micro_old');
  });

  testWidgets('short: «ناقصك», the bar, «اشتريها» disabled, no impact', (
    tester,
  ) async {
    final (container, economy) = await pumpLinesApp(
      tester,
      state: playerState(jenehat: 1200),
      location: '/lines/vehicle/micro_old',
    );
    expect(shows('ناقصك ٣٠٠ ج'), findsOneWidget);
    expect(find.textContaining('بعد الشرا'), findsNothing);
    await tester.tap(find.byKey(VehicleSheet.buyKey));
    await tester.pumpAndSettle();
    expect(container.read(economyViewProvider).jenehat, 1200);
    expect(locationOf(container), '/lines/vehicle/micro_old');
    expect(economy.service.view.owns(SkuKind.vehicle, 'micro_old'), isFalse);
  });

  testWidgets('«اشتريها» spends the price once, makes it current and '
      'closes to the map', (tester) async {
    final (container, economy) = await pumpLinesApp(
      tester,
      state: playerState(jenehat: 2000),
      location: '/lines/vehicle/micro_old',
    );
    await tester.tap(find.byKey(VehicleSheet.buyKey));
    await tester.tap(find.byKey(VehicleSheet.buyKey), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(locationOf(container), '/lines');
    expect(container.read(economyViewProvider).jenehat, 500);
    expect(economy.service.view.owns(SkuKind.vehicle, 'micro_old'), isTrue);
    expect(labelled('ميكروباص قديم، عربيتك دلوقتي'), findsOneWidget);
  });

  testWidgets('a failed write stays with the retry line; the retry is the '
      'same request (the other outcomes: vehicle_purchase_test)', (
    tester,
  ) async {
    final interceptor = FailingInterceptor();
    final (container, economy) = await pumpLinesApp(
      tester,
      state: playerState(jenehat: 2000),
      location: '/lines/vehicle/micro_old',
      interceptor: interceptor,
    );
    interceptor.failInserts = true;
    await tester.tap(find.byKey(VehicleSheet.buyKey));
    await tester.pumpAndSettle();
    expect(find.byKey(VehicleSheet.retryKey), findsOneWidget);
    expect(locationOf(container), '/lines/vehicle/micro_old');
    expect(container.read(economyViewProvider).jenehat, 2000);
    interceptor.failInserts = false;
    await tester.tap(find.byKey(VehicleSheet.buyKey));
    await tester.pumpAndSettle();
    expect(locationOf(container), '/lines');
    expect(container.read(economyViewProvider).jenehat, 500);
    final pending = await tester.runAsync(economy.service.pendingOps);
    expect(pending, hasLength(1));
  });

  testWidgets('a balance change while open flips short and affordable', (
    tester,
  ) async {
    final (container, economy) = await pumpLinesApp(
      tester,
      state: playerState(jenehat: 1600),
      location: '/lines/vehicle/micro_old',
    );
    expect(find.byKey(VehicleSheet.shortfallKey), findsNothing);
    // Another purchase spends below the price: the sheet goes short.
    await economy.service.buy(
      economy.service.newRequestId(),
      kind: SkuKind.chapter,
      skuId: 'ch3_shabka',
    );
    await tester.pumpAndSettle();
    expect(container.read(economyViewProvider).jenehat, lessThan(1500));
    expect(find.byKey(VehicleSheet.shortfallKey), findsOneWidget);
    expect(find.byType(VehicleSheet), findsOneWidget);
  });

  group('closing spends nothing', () {
    for (final (way, close) in <(String, Future<void> Function(WidgetTester))>[
      (
        '«لسه»',
        (tester) async {
          await tester.tap(find.byKey(VehicleSheet.laterKey));
          await tester.pumpAndSettle();
        },
      ),
      (
        '✕',
        (tester) async {
          await tester.tap(find.byKey(VehicleSheet.closeKey));
          await tester.pumpAndSettle();
        },
      ),
      ('back', pressBack),
      (
        'a swipe',
        (tester) async {
          final height = tester.getSize(find.byType(AppSheet)).height;
          await tester.drag(
            find.byKey(AppSheet.grabberKey),
            Offset(0, height * 0.4),
          );
          await tester.pumpAndSettle();
        },
      ),
    ]) {
      testWidgets(way, (tester) async {
        final (container, _) = await pumpLinesApp(
          tester,
          state: playerState(jenehat: 2000),
          location: '/lines/vehicle/micro_old',
        );
        await close(tester);
        expect(locationOf(container), '/lines');
        expect(container.read(economyViewProvider).jenehat, 2000);
      });
    }
  });

  group('nothing to buy (US4)', () {
    testWidgets('the starter: the master\'s, one «تمام», no price', (
      tester,
    ) async {
      final (container, _) = await pumpLinesApp(
        tester,
        location: '/lines/vehicle/tuktuk',
      );
      expect(shows('دي عربية المعلم، وانت شغال عليها'), findsOneWidget);
      expect(find.byKey(VehicleSheet.buyKey), findsNothing);
      expect(find.textContaining('السعر'), findsNothing);
      await tester.tap(find.byKey(VehicleSheet.doneKey));
      await tester.pumpAndSettle();
      expect(locationOf(container), '/lines');
    });

    testWidgets('a bought vehicle is yours', (tester) async {
      await pumpLinesApp(
        tester,
        state: playerState(owned: {microOld}),
        location: '/lines/vehicle/micro_old',
      );
      expect(shows('دي عربيتك'), findsOneWidget);
      expect(find.byKey(VehicleSheet.doneKey), findsOneWidget);
    });

    testWidgets('a vehicle after one the player lacks', (tester) async {
      await pumpLinesApp(tester, location: '/lines/vehicle/micro_new');
      expect(shows('اشتري ميكروباص قديم الأول'), findsOneWidget);
      expect(find.byKey(VehicleSheet.buyKey), findsNothing);
    });

    testWidgets('a vehicle with no price', (tester) async {
      final pack = artboardLines();
      final catalog = pack['catalog']! as Map<String, Object?>;
      catalog['prices'] = [
        for (final price in catalog['prices']! as List<Object?>)
          if ((price! as Map<String, Object?>)['sku_id'] != 'micro_old') price,
      ];
      await pumpLinesApp(
        tester,
        pack: pack,
        location: '/lines/vehicle/micro_old',
      );
      expect(shows('العربية دي مش للبيع دلوقتي'), findsOneWidget);
    });
  });

  testWidgets('an id the pack lacks goes to the map', (tester) async {
    final (container, _) = await pumpLinesApp(
      tester,
      pack: samplePackJsonForLines(),
      location: '/lines/vehicle/micro_safar',
    );
    expect(locationOf(container), '/lines');
  });
}
