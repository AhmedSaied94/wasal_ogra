import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/bootstrap/app.dart' show appLocale;
import 'package:wassal/core/routing/routes.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

import '../design/samples/lines.dart';
import '../design/samples/buy_vehicle.dart';
import '../helpers/economy.dart' show FailingInterceptor;
import '../helpers/lines.dart' show playerState;
import '../helpers/screens.dart';
import 'minimum_sizes_test.dart' show expectMinimumSizes;

import 'package:wassal/features/lines/presentation/vehicle_sheet.dart';

// `BuyVehicle`'s minimum sizes (specs/014-m09-lines-vehicles, T031, T047,
// T058, T106; constitution XI): targets ≥ 44×44 and text ≥ 12 at text scale
// 1.0 and 1.3, on the small, the tall-narrow and the reference phone, with
// nothing cut short — the artboard's state, the shortfall sheet with
// «ناقصك» and the bar, the plain affordable sheet, the owned sheet and the
// not-for-sale one.

const _phones = [Size(360, 640), Size(360, 800), Size(390, 844)];

void main() {
  late Set<String> titles;

  setUpAll(() async {
    final l10n = await AppLocalizations.delegate.load(appLocale);
    titles = {for (final d in destinations) d.title(l10n)};
  });

  final states = <(String, Future<void> Function(WidgetTester, Size, double))>[
    (
      'artboard',
      (tester, size, scale) =>
          pumpBuyVehicle(tester, size: size, textScale: scale),
    ),
    (
      'short',
      (tester, size, scale) =>
          pumpBuyVehicleShort(tester, size: size, textScale: scale),
    ),
    (
      'plain',
      (tester, size, scale) =>
          pumpBuyVehiclePlain(tester, size: size, textScale: scale),
    ),
    (
      'owned',
      (tester, size, scale) =>
          pumpBuyVehicleOwned(tester, size: size, textScale: scale),
    ),
    (
      'not for sale',
      (tester, size, scale) =>
          pumpBuyVehicleNoPrice(tester, size: size, textScale: scale),
    ),
    (
      'failed write',
      (tester, size, scale) async {
        final interceptor = FailingInterceptor();
        await pumpLinesBoard(
          tester,
          location: '/lines/vehicle/micro_old',
          player: playerState(jenehat: 2000),
          size: size,
          textScale: scale,
          interceptor: interceptor,
        );
        interceptor.failInserts = true;
        await tester.tap(find.byKey(VehicleSheet.buyKey));
        await tester.pumpAndSettle();
      },
    ),
  ];

  for (final (name, pump) in states) {
    for (final size in _phones) {
      for (final scale in textScales) {
        testWidgets(
          'BuyVehicle $name · ${size.width.round()}×'
          '${size.height.round()} · ×$scale',
          (tester) => expectMinimumSizes(
            tester,
            titles,
            (tester) => pump(tester, size, scale),
          ),
        );
      }
    }
  }
}
