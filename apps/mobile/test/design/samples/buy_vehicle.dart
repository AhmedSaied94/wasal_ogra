import 'package:content_models/content_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show Size;
import 'package:wassal/core/l10n/digit_style.dart';

import '../../helpers/progress.dart';
import '../../helpers/synthetic_packs.dart';
import 'lines.dart';

// The BuyVehicle boards over Lines. `BuyVehicle`: the new microbus at 5,000
// with 6,100 saved, in chapter 4 with the salon's next piece «النجفة» at
// 3,500, so the impact line leaves 2,400 for it. `BuyVehicleShort`,
// `BuyVehicleOwned` and `BuyVehicleNotForSale` (2026-10-29): the players of
// `LinesFirst` and `LinesOwned`.

Map<String, Object?> buyVehiclePack() {
  final json = artboardLines();
  for (final item in entries(json, 'items')) {
    if (item['item_id'] == 'salon.nish') item['name'] = {'ar-EG': 'النجفة'};
  }
  final catalog = json['catalog']! as Map<String, Object?>;
  for (final price in entries(catalog, 'prices')) {
    if (price['sku_id'] == 'salon.nish') price['amount'] = 3500;
  }
  return json;
}

Future<ProviderContainer> pumpBuyVehicle(
  WidgetTester tester, {
  DigitStyle digits = DigitStyle.arabicIndic,
  Size? size,
  double textScale = 1.0,
}) => pumpLinesBoard(
  tester,
  location: '/lines/vehicle/micro_new',
  pack: buyVehiclePack(),
  player: boardPlayer(jenehat: 6100, owned: const {microOld, shabka}),
  digits: digits,
  size: size,
  textScale: textScale,
);

/// The plain affordable sheet, no impact line (T104, R12): the money left
/// covers the goal.
Future<ProviderContainer> pumpBuyVehiclePlain(
  WidgetTester tester, {
  DigitStyle digits = DigitStyle.arabicIndic,
  Size? size,
  double textScale = 1.0,
}) => pumpLinesBoard(
  tester,
  location: '/lines/vehicle/micro_new',
  pack: buyVehiclePack(),
  player: boardPlayer(jenehat: 9000, owned: const {microOld, shabka}),
  digits: digits,
  size: size,
  textScale: textScale,
);

/// `BuyVehicleShort`: the old microbus at 3,200 with 1,240 saved.
Future<ProviderContainer> pumpBuyVehicleShort(
  WidgetTester tester, {
  DigitStyle digits = DigitStyle.arabicIndic,
  Size? size,
  double textScale = 1.0,
}) => pumpLinesBoard(
  tester,
  location: '/lines/vehicle/micro_old',
  pack: draftBoards(),
  player: firstPlayer(),
  digits: digits,
  size: size,
  textScale: textScale,
);

/// `BuyVehicleOwned`: the old microbus, bought.
Future<ProviderContainer> pumpBuyVehicleOwned(
  WidgetTester tester, {
  DigitStyle digits = DigitStyle.arabicIndic,
  Size? size,
  double textScale = 1.0,
}) => pumpLinesBoard(
  tester,
  location: '/lines/vehicle/micro_old',
  pack: draftBoards(),
  player: ownedPlayer(),
  digits: digits,
  size: size,
  textScale: textScale,
);

/// `BuyVehicleNotForSale`: the new microbus, before the old one is bought.
/// The brief asked for a vehicle that opens no line here (two benefit
/// tiles), so خط السوق opens after خط الجامعة instead.
Future<ProviderContainer> pumpBuyVehicleNotForSale(
  WidgetTester tester, {
  DigitStyle digits = DigitStyle.arabicIndic,
  Size? size,
  double textScale = 1.0,
}) {
  final pack = artboardLines();
  // The boards of 2026-10-29 name it as the release draft does.
  for (final vehicle in entries(pack, 'vehicles')) {
    if (vehicle['vehicle_id'] == 'micro_old') {
      vehicle['name'] = {'ar-EG': 'الميكروباص القديم'};
    }
  }
  for (final line in entries(pack, 'lines')) {
    if (line['line_id'] == 'line_souq') {
      line['unlock'] = {'kind': 'line_complete', 'line_id': 'line_gamaa'};
    }
  }
  return pumpLinesBoard(
    tester,
    location: '/lines/vehicle/micro_new',
    pack: pack,
    player: firstPlayer(),
    digits: digits,
    size: size,
    textScale: textScale,
  );
}

/// A vehicle with no catalog price (T104, R12: no board draws it):
/// ميكروباص سفر, its sheet as `BuyVehicleNotForSale` with no price card.
Future<ProviderContainer> pumpBuyVehicleNoPrice(
  WidgetTester tester, {
  DigitStyle digits = DigitStyle.arabicIndic,
  Size? size,
  double textScale = 1.0,
}) {
  final pack = artboardLines();
  final catalog = pack['catalog']! as Map<String, Object?>;
  catalog['prices'] = [
    for (final price in catalog['prices']! as List<Object?>)
      if ((price! as Map<String, Object?>)['sku_id'] != 'micro_safar') price,
  ];
  return pumpLinesBoard(
    tester,
    location: '/lines/vehicle/micro_safar',
    pack: pack,
    player: boardPlayer(
      owned: const {microOld, (SkuKind.vehicle, 'micro_new'), shabka},
    ),
    digits: digits,
    size: size,
    textScale: textScale,
  );
}
