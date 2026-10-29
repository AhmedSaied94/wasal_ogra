import 'package:content_models/content_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show Size;
import 'package:wassal/core/economy/domain/economy_state.dart';
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/core/sync/server_status.dart';

import '../../helpers/economy.dart' show FailingInterceptor;
import '../../helpers/lines.dart';
import '../../helpers/progress.dart';
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
  ServerStatusState serverStatus = const ServerStatusState(),
  FailingInterceptor? interceptor,
}) async {
  // The frame is set before the first one, where the map scrolls to its
  // focus (R2-2).
  const board = Size(390, 844);
  if (size == null) {
    applyDesignSurface(tester, board, topInset: designTopInset);
  }
  final (container, _) = await pumpLinesApp(
    tester,
    pack: pack ?? artboardLines(),
    state: player ?? boardPlayer(),
    location: location,
    size: size ?? board,
    digits: digits,
    textScale: textScale,
    serverStatus: serverStatus,
    interceptor: interceptor,
  );
  return container;
}

/// `Lines`.
Future<ProviderContainer> pumpLines(
  WidgetTester tester, {
  DigitStyle digits = DigitStyle.arabicIndic,
  Size? size,
  double textScale = 1.0,
}) => pumpLinesBoard(tester, digits: digits, size: size, textScale: textScale);

/// خط الجامعة's what's new as the boards of 2026-10-29 and the release
/// draft write it: guillemets, and «أبو سمّاعة» held together.
const gamaaWhatsNew = 'نص الأجرة، الدفع الجماعي، «أنا دافع!»، أبو سمّاعة';

/// The boards of 2026-10-29 (`LinesFirst`, `LinesOwned`, `LineDetailsStory`,
/// `LineDetailsDone`, `BuyVehicleShort`, `BuyVehicleOwned`): the release
/// draft's two lines and two vehicles ([draftShaped]), with the boards'
/// fares and خط الجامعة's what's new.
Map<String, Object?> draftBoards() {
  final json = draftShaped();
  return {
    ...json,
    'lines': [
      for (final line
          in (json['lines']! as List<Object?>).cast<Map<String, Object?>>())
        switch (line['line_id']) {
          'line_hay' => {...line, 'display_fare_piasters': 700},
          'line_gamaa' => {
            ...line,
            'display_fare_piasters': 850,
            'whats_new': {'ar-EG': gamaaWhatsNew},
          },
          _ => line,
        },
    ],
  };
}

/// [n] trips of [line] from the first, with [stars] each in turn.
Map<String, int> playedOf(String line, List<int> stars) => {
  for (var n = 1; n <= stars.length; n++) _t(line, n): stars[n - 1],
};

/// `LinesFirst`'s player: the tuktuk only, خط الحي at 14 of 60 with the
/// 8th next, 1,240 JENEHAT and 85 BONAT.
EconomyState Function(int nowMs) firstPlayer() => playerState(
  jenehat: 1240,
  bonat: 85,
  stars: playedOf('line_hay', List.filled(7, 2)),
);

/// خط الحي done at 54 of 60, as `LineDetailsDone` stars its cells.
const hayDoneStars = [
  3,
  3,
  2,
  3,
  3,
  2,
  3,
  3,
  1,
  3,
  3,
  2,
  3,
  3,
  3,
  2,
  3,
  3,
  3,
  3,
];

/// `LinesOwned`'s player (and `LineDetailsDone`'s): the old microbus
/// bought, خط الحي done at 54 of 60, خط الجامعة at 27 of 90 with the 12th
/// next.
EconomyState Function(int nowMs) ownedPlayer() => playerState(
  jenehat: 1240,
  bonat: 85,
  stars: {
    ...playedOf('line_hay', hayDoneStars),
    ...playedOf('line_gamaa', const [3, 3, 2, 3, 2, 3, 2, 3, 2, 3, 1]),
  },
  owned: {microOld},
);

/// `LinesFirst`.
Future<ProviderContainer> pumpLinesFirst(
  WidgetTester tester, {
  DigitStyle digits = DigitStyle.arabicIndic,
  Size? size,
  double textScale = 1.0,
}) => pumpLinesBoard(
  tester,
  pack: draftBoards(),
  player: firstPlayer(),
  digits: digits,
  size: size,
  textScale: textScale,
);

/// `LinesOwned`.
Future<ProviderContainer> pumpLinesOwned(
  WidgetTester tester, {
  DigitStyle digits = DigitStyle.arabicIndic,
  Size? size,
  double textScale = 1.0,
}) => pumpLinesBoard(
  tester,
  pack: draftBoards(),
  player: ownedPlayer(),
  digits: digits,
  size: size,
  textScale: textScale,
);

/// `Lines` with خط الحي done at three stars on every trip (T104, R12: a
/// state no board draws).
Future<ProviderContainer> pumpLinesDoneAtThree(
  WidgetTester tester, {
  DigitStyle digits = DigitStyle.arabicIndic,
  Size? size,
  double textScale = 1.0,
}) => pumpLinesBoard(
  tester,
  player: playerState(
    jenehat: 1240,
    bonat: 85,
    stars: {
      for (var n = 1; n <= 20; n++) _t('line_hay', n): 3,
      for (var n = 1; n <= gamaaStars.length; n++)
        _t('line_gamaa', n): gamaaStars[n - 1],
    },
    owned: {microOld},
  ),
  digits: digits,
  size: size,
  textScale: textScale,
);

/// `Lines` offline: the BONAT pill says the shop needs the network (T104).
Future<ProviderContainer> pumpLinesOffline(
  WidgetTester tester, {
  DigitStyle digits = DigitStyle.arabicIndic,
  Size? size,
  double textScale = 1.0,
}) => pumpLinesBoard(
  tester,
  serverStatus: const ServerStatusState(reach: Reach.offline),
  digits: digits,
  size: size,
  textScale: textScale,
);

/// `Lines` on a 360×640 phone at 1.3× (T104, R12: a composed state).
Future<ProviderContainer> pumpLinesSmall(
  WidgetTester tester, {
  DigitStyle digits = DigitStyle.arabicIndic,
}) => pumpLinesBoard(
  tester,
  digits: digits,
  size: const Size(360, 640),
  textScale: 1.3,
);
