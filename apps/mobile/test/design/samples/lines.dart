import 'package:content_models/content_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show Size;
import 'package:wassal/core/economy/domain/economy_state.dart';
import 'package:wassal/core/l10n/digit_style.dart';

import '../../helpers/lines.dart';
import '../../helpers/progress.dart';
import '../../helpers/surfaces.dart';
import '../../helpers/synthetic_packs.dart';
import '../design_check.dart';

// The three Lines boards' player (specs/014-m09-lines-vehicles, T030,
// T046, T058), on `artboardLines()`: 1,240 JENEHAT and 85 BONAT; the old
// microbus; خط الحي done at 54 of 60; خط الجامعة 1–11 done with the
// `LineDetails` board's stars (25: the header's 27 doesn't add up,
// research R4), its 10th a story trip, the 12th next, the 20th a story
// trip waiting for the shabka.

String _t(String line, int n) => '$line.${n.toString().padLeft(2, '0')}';

/// `LineDetails`' cells, 1 to 11.
const gamaaStars = [3, 3, 2, 3, 2, 2, 1, 3, 2, 3, 1];

Map<String, int> boardStars() => {
  // 54 of 60: fourteen at three, six at two.
  for (var n = 1; n <= 20; n++) _t('line_hay', n): n <= 14 ? 3 : 2,
  for (var n = 1; n <= gamaaStars.length; n++)
    _t('line_gamaa', n): gamaaStars[n - 1],
};

EconomyState Function(int nowMs) boardPlayer({
  int jenehat = 1240,
  Set<(SkuKind, String)> owned = const {microOld},
}) =>
    playerState(jenehat: jenehat, bonat: 85, stars: boardStars(), owned: owned);

/// The app at [location] on the boards' frame (or [size]) at [textScale].
Future<ProviderContainer> pumpLinesBoard(
  WidgetTester tester, {
  String location = '/lines',
  Map<String, Object?>? pack,
  EconomyState Function(int nowMs)? player,
  DigitStyle digits = DigitStyle.arabicIndic,
  Size? size,
  double textScale = 1.0,
}) async {
  final (container, _) = await pumpLinesApp(
    tester,
    pack: pack ?? artboardLines(),
    state: player ?? boardPlayer(),
    location: location,
    digits: digits,
    textScale: textScale,
  );
  if (size == null) {
    applyDesignSurface(tester, const Size(390, 844), topInset: designTopInset);
  } else {
    applySurfaceSize(tester, size);
  }
  await tester.pumpAndSettle();
  return container;
}

/// `Lines`.
Future<ProviderContainer> pumpLines(
  WidgetTester tester, {
  DigitStyle digits = DigitStyle.arabicIndic,
  Size? size,
  double textScale = 1.0,
}) => pumpLinesBoard(tester, digits: digits, size: size, textScale: textScale);
