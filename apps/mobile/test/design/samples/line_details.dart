import 'package:content_models/content_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show Size;
import 'package:wassal/core/economy/domain/economy_state.dart';
import 'package:wassal/core/l10n/digit_style.dart';

import '../../helpers/lines.dart';
import '../../helpers/progress.dart';
import '../../helpers/synthetic_packs.dart';
import 'lines.dart';

// The LineDetails boards over Lines. `LineDetails`: خط الجامعة with 12
// next, the board's stars per cell, the 10th a story trip done, the 20th a
// story trip locked. `LineDetailsStory`, `LineDetailsDone` and
// `LineDetailsLocked` (2026-10-29): their own states below.

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

/// خط الجامعة as `LineDetailsStory` stars it: .19–.22 played while the
/// story trip .18 waited for the shabka, 58 of 90 in all.
const gamaaStoryStars = {
  1: 3, 2: 3, 3: 2, 4: 3, 5: 3, 6: 3, 7: 1, 8: 3, 9: 3, 10: 2, 11: 3, //
  12: 3, 13: 3, 14: 3, 15: 2, 16: 3, 17: 3, 19: 3, 20: 3, 21: 3, 22: 3,
};

/// `LineDetailsStory`'s player: the shabka bought, so .18 is next again
/// and .23 playable, six rows and no hint (FR-025).
EconomyState Function(int nowMs) storyPlayer() => playerState(
  jenehat: 1240,
  bonat: 85,
  stars: {
    ...playedOf('line_hay', hayDoneStars),
    for (final MapEntry(:key, :value) in gamaaStoryStars.entries)
      _t('line_gamaa', key): value,
  },
  owned: {microOld, shabka},
);

/// `LineDetailsStory`.
Future<ProviderContainer> pumpLineDetailsStory(
  WidgetTester tester, {
  DigitStyle digits = DigitStyle.arabicIndic,
  Size? size,
  double textScale = 1.0,
}) => pumpLinesBoard(
  tester,
  location: '/lines/line_gamaa',
  pack: draftBoards(),
  player: storyPlayer(),
  digits: digits,
  size: size,
  textScale: textScale,
);

/// A line of under 20 trips (T104, R12): خط السوق's two, open.
Future<ProviderContainer> pumpLineDetailsShort(
  WidgetTester tester, {
  DigitStyle digits = DigitStyle.arabicIndic,
  Size? size,
  double textScale = 1.0,
}) => pumpLinesBoard(
  tester,
  location: '/lines/line_souq',
  player: boardPlayer(
    owned: const {microOld, (SkuKind.vehicle, 'micro_new'), shabka},
  ),
  digits: digits,
  size: size,
  textScale: textScale,
);

/// `LineDetailsDone`: خط الحي done at 54 of 60.
Future<ProviderContainer> pumpLineDetailsDone(
  WidgetTester tester, {
  DigitStyle digits = DigitStyle.arabicIndic,
  Size? size,
  double textScale = 1.0,
}) => pumpLinesBoard(
  tester,
  location: '/lines/line_hay',
  pack: draftBoards(),
  player: ownedPlayer(),
  digits: digits,
  size: size,
  textScale: textScale,
);

/// `LineDetailsLocked`: خط المصيف's twenty trips, behind خط السوق.
Future<ProviderContainer> pumpLineDetailsLocked(
  WidgetTester tester, {
  DigitStyle digits = DigitStyle.arabicIndic,
  Size? size,
  double textScale = 1.0,
}) => pumpLinesBoard(
  tester,
  location: '/lines/line_masyaf',
  pack: _withTrips(artboardLines(), 'line_masyaf', 20),
  digits: digits,
  size: size,
  textScale: textScale,
);

/// [pack] with [line] at [count] trips, each a copy of its first.
Map<String, Object?> _withTrips(
  Map<String, Object?> pack,
  String line,
  int count,
) {
  final trips = (pack['trips']! as List<Object?>).cast<Map<String, Object?>>();
  final first = trips.firstWhere((t) => t['trip_id'] == _t(line, 1));
  return {
    ...pack,
    'trips': [
      for (final trip in trips)
        if (trip['line_id'] != line) trip,
      for (var n = 1; n <= count; n++) {...first, 'trip_id': _t(line, n)},
    ],
  };
}

String _t(String line, int n) => '$line.${n.toString().padLeft(2, '0')}';
