import 'package:content_models/content_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show Size;
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:wassal/core/economy/domain/economy_state.dart';
import 'package:wassal/core/progress/application/pending_rewards_provider.dart';
import 'package:wassal/core/progress/domain/rewards.dart';
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/features/apartment/application/apartment_providers.dart';
import 'package:wassal/features/apartment/presentation/piece_sheet.dart';

import '../../helpers/lines.dart';
import '../../helpers/progress.dart';
import '../../helpers/surfaces.dart';
import '../../helpers/synthetic_packs.dart';
import '../design_check.dart';

// The seven apartment boards the owner drew on 2026-10-31 (specs/015-m10-
// apartment-story, T131), all on `releaseDraftPack()`: `AptGoalLine`,
// `AptGoalVehicle`, `AptRoomsAffordable`, `AptRoomsBought`, `AptRoomsDone`,
// `PieceAffordable` and `RoomDonePending`. Each is the board's sample state,
// 390×844 at DPR 1 with the 36 pt status inset, RTL.

const _sitara = (SkuKind.item, 'salon.sitara');
const _nagfa = (SkuKind.item, 'salon.nagafa');
const _nish = (SkuKind.item, 'salon.nish');
const _antreeh = (SkuKind.item, 'salon.antreeh');

/// خط الحي's first [n] regular trips finished.
Map<String, int> hayTrips(int n) => {
  for (var i = 1; i <= n; i++) 'line_hay.${i.toString().padLeft(2, '0')}': 1,
};

/// Chapters 1 to 3 done: the line, the old microbus and the shabka.
const _beforeSalon = {microOld, shabka};

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required String location,
  required EconomyState Function(int nowMs) state,
  List<Override> overrides = const [],
  required DigitStyle digits,
  Size? size,
  double textScale = 1.0,
}) async {
  final (container, _) = await pumpLinesApp(
    tester,
    pack: releaseDraftPack(),
    digits: digits,
    textScale: textScale,
    location: location,
    // The goal bar animates and the clock idles: nothing settles.
    settle: false,
    state: state,
    overrides: overrides,
  );
  if (size == null) {
    applyDesignSurface(tester, const Size(390, 844), topInset: designTopInset);
  } else {
    applySurfaceSize(tester, size);
  }
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  return container;
}

/// `AptGoalLine`: chapter 1, 8 of خط الحي's 19 regular trips, 2,200 in hand.
Future<ProviderContainer> pumpAptGoalLine(
  WidgetTester tester, {
  DigitStyle digits = DigitStyle.arabicIndic,
  Size? size,
  double textScale = 1.0,
}) => _pump(
  tester,
  location: '/apartment',
  digits: digits,
  size: size,
  textScale: textScale,
  state: playerState(jenehat: 2200, stars: hayTrips(8)),
);

/// `AptGoalVehicle`: chapter 2, 3,240 in hand, the old microbus (3,200) not
/// owned.
Future<ProviderContainer> pumpAptGoalVehicle(
  WidgetTester tester, {
  DigitStyle digits = DigitStyle.arabicIndic,
  Size? size,
  double textScale = 1.0,
}) => _pump(
  tester,
  location: '/apartment',
  digits: digits,
  size: size,
  textScale: textScale,
  state: playerState(jenehat: 3240, stars: hayTrips(19)),
);

/// The boards count two open requests with the third taken: the draft's
/// الأنتريه (أبو العروسة, 5 BONAT) is in the player's claimed set. The
/// economy only takes a request whose piece is owned, and the boards' player
/// doesn't own it, so the set is the base's.
const _claimedAntreeh = {'req_antreeh_classic'};

/// `AptRoomsAffordable`: chapter 4, الستاير owned, 1,180 in hand, النجفة
/// (1,050) next and affordable, and a claimed request's 5 BONAT not yet
/// confirmed: the pending provider reports them, as the boards draw the
/// chip (the base already holds the claim, see [_claimedAntreeh]).
Future<ProviderContainer> pumpAptRoomsAffordable(
  WidgetTester tester, {
  DigitStyle digits = DigitStyle.arabicIndic,
  Size? size,
  double textScale = 1.0,
}) => _pump(
  tester,
  location: '/apartment',
  digits: digits,
  size: size,
  textScale: textScale,
  overrides: [
    pendingRewardsProvider.overrideWithValue(const [
      PendingReward(RequestReward('req_antreeh_classic'), 5),
    ]),
  ],
  state: playerState(
    jenehat: 1180,
    stars: hayTrips(19),
    owned: {..._beforeSalon, _sitara},
    styles: const {'salon.sitara': 'plain'},
    requestsClaimed: _claimedAntreeh,
  ),
);

/// `AptRoomsBought`: النجفة كريستال just bought from its sheet (1,180 to
/// 130), the end frame of the drop-in with سلمى's comment.
Future<ProviderContainer> pumpAptRoomsBought(
  WidgetTester tester, {
  DigitStyle digits = DigitStyle.arabicIndic,
  Size? size,
  double textScale = 1.0,
}) async {
  final container = await _pump(
    tester,
    location: '/apartment/item/salon.nagafa',
    digits: digits,
    size: size,
    textScale: textScale,
    state: playerState(
      jenehat: 1180,
      stars: hayTrips(19),
      owned: {..._beforeSalon, _sitara},
      styles: const {'salon.sitara': 'plain'},
      requestsClaimed: _claimedAntreeh,
    ),
  );
  await tester.tap(find.byKey(PieceSheet.buyKey));
  // The sheet leaves, the drop-in ends and the bubble pops.
  for (var i = 0; i < 24; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  return container;
}

/// `AptRoomsDone`: all four pieces owned, the requests all taken, the
/// rewards confirmed and `RoomDone` closed with «بعدين», so the goal scene
/// waits.
Future<ProviderContainer> pumpAptRoomsDone(
  WidgetTester tester, {
  DigitStyle digits = DigitStyle.arabicIndic,
  Size? size,
  double textScale = 1.0,
}) => _pump(
  tester,
  location: '/apartment',
  digits: digits,
  size: size,
  textScale: textScale,
  state: playerState(
    jenehat: 1325,
    stars: hayTrips(19),
    owned: {..._beforeSalon, _sitara, _nagfa, _nish, _antreeh},
    styles: const {
      'salon.sitara': 'plain',
      'salon.nagafa': 'crystal',
      'salon.nish': 'golden',
      'salon.antreeh': 'classic',
    },
    requestsClaimed: {
      'req_antreeh_classic',
      'req_nagafa_crystal',
      'req_nish_golden',
    },
  ),
);

/// `PieceAffordable`: النجفة's sheet with 1,180 in hand, أم العروسة's request
/// on كريستال and مودرن selected.
Future<ProviderContainer> pumpPieceAffordable(
  WidgetTester tester, {
  DigitStyle digits = DigitStyle.arabicIndic,
  Size? size,
  double textScale = 1.0,
}) async {
  final container = await _pump(
    tester,
    location: '/apartment/item/salon.nagafa',
    digits: digits,
    size: size,
    textScale: textScale,
    state: playerState(
      jenehat: 1180,
      stars: hayTrips(19),
      owned: {..._beforeSalon, _sitara},
      styles: const {'salon.sitara': 'plain'},
      requestsClaimed: _claimedAntreeh,
    ),
  );
  container
      .read(pieceStyleMemoryProvider.notifier)
      .choose('salon.nagafa', 'modern');
  await tester.pump(const Duration(milliseconds: 50));
  return container;
}

/// `RoomDonePending`: the last piece (الأنتريه) bought offline over the tab,
/// which completes the salon and chapter 4: 25 and 20 BONAT on their way.
Future<ProviderContainer> pumpRoomDonePending(
  WidgetTester tester, {
  DigitStyle digits = DigitStyle.arabicIndic,
  Size? size,
  double textScale = 1.0,
}) async {
  final container = await _pump(
    tester,
    location: '/apartment/item/salon.antreeh',
    digits: digits,
    size: size,
    textScale: textScale,
    state: playerState(
      jenehat: 1600,
      stars: hayTrips(19),
      owned: {..._beforeSalon, _sitara, _nagfa, _nish},
      styles: const {
        'salon.sitara': 'plain',
        'salon.nagafa': 'crystal',
        'salon.nish': 'golden',
      },
      requestsClaimed: {
        'req_antreeh_classic',
        'req_nagafa_crystal',
        'req_nish_golden',
      },
    ),
  );
  await tester.tap(find.byKey(PieceSheet.buyKey));
  for (var i = 0; i < 16; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  return container;
}
