import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show Size;
import 'package:wassal/core/l10n/digit_style.dart';

import '../../helpers/progress.dart';
import '../../helpers/synthetic_packs.dart';
import 'lines.dart';

// `BuyVehicle` over Lines: the new microbus at 5,000 with 6,100 saved, in
// chapter 4 with the salon's next piece «النجفة» at 3,500, so the impact
// line leaves 2,400 for it.

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
