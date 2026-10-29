import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show Size;
import 'package:wassal/core/l10n/digit_style.dart';

import 'lines.dart';

// `LineDetails` over Lines: خط الجامعة with 12 next, the board's stars per
// cell, the 10th a story trip done, the 20th a story trip locked.

Future<ProviderContainer> pumpLineDetails(
  WidgetTester tester, {
  DigitStyle digits = DigitStyle.arabicIndic,
  Size? size,
  double textScale = 1.0,
}) => pumpLinesBoard(
  tester,
  location: '/lines/line_gamaa',
  digits: digits,
  size: size,
  textScale: textScale,
);
