import 'package:flutter_test/flutter_test.dart';

import 'design_check.dart';
import 'samples/apt_states.dart';

// The apartment's boards of 2026-10-31 against their measured boxes
// (specs/015-m10-apartment-story, T131). Every tap box is matched within 2 pt
// unless listed. The samples play the release draft, whose copy wins over the
// boards' (owner decision 2026-10-31); a text of another length can move a
// box, and each such case is listed here.
//
// AptGoalVehicle: box 22's label is the app's digits, the board's is spoken.
//
// AptRoomsAffordable, AptRoomsBought:
// - the board hard-codes where each chip hangs (box 25, 28, 31); the app
//   hangs it on the draft item's slot, so the chips move (offsets), and the
//   النيش chip is 128 wide against the board's 134 (the draft's name and
//   price) and gets 3 pt;
// - the board orders the grid [الستاير, النيش; الأنتريه, النجفة], the app
//   follows the draft's `order` [الستاير, النجفة; النيش, الأنتريه], so the
//   three cells move (offsets); box 42's label is spoken on the board;
// - the tabs are drawn 36 high (flex 20/20/25 as drawn) but their hit row
//   is 44, the board's 4 above and below the face (SC-006), so a tab's box
//   is 4 taller each way (tolerance 4.5), and a locked tab takes no tap;
// - the strip and the chapter bar's tagline carry the draft's text: the
//   board's «زيارة أهل العروسة» is the draft's «العيلة في الصالون», and
//   «أهل العروسة جايين الخميس» is «الصالون هو اللي بيحكي عن البيت» (not tap
//   boxes, so only the goldens differ).
//
// AptRoomsDone: «شوف المشهد» (box 9) is 126 wide here, 117 on the board:
// Flutter measures the label wider, so the pill's far side moves 12 pt. The
// bar is 2 pt taller than drawn (28 + 6 + 8 and its padding), so the tabs
// below it sit 2 lower, and their 44 hit rows reach 6 below the board's.
//
// PieceAffordable: the sheet's 14 pt bottom padding (the board's 11.8) and
// its content make it 703 high, not 700: it opens 3 pt higher and the boxes
// below the header follow (3.2 pt). «اقفل» is the app-wide «قفل».
//
// RoomDonePending: the board pins its dialog 17 pt below where the app
// centres it, both 542 high (offsets of -16); «بعدين» is 63 wide there and
// 56 here, the same centre (3.5 pt).

void main() {
  testWidgets('AptGoalLine: the boxes', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpAptGoalLine(tester);
    expectLayoutMatches(tester, 'AptGoalLine');
    semantics.dispose();
  });

  testWidgets('AptGoalVehicle: the boxes', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpAptGoalVehicle(tester);
    expectLayoutMatches(
      tester,
      'AptGoalVehicle',
      pairings: const {22: 'اشتري الميكروباص القديم بـ٣٬٢٠٠ جنيه'},
    );
    semantics.dispose();
  });

  testWidgets('AptRoomsAffordable: the boxes', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpAptRoomsAffordable(tester);
    expectLayoutMatches(
      tester,
      'AptRoomsAffordable',
      pairings: const {
        42: 'النجفة، تقدر تشتريها، ١٬٠٥٠ جنيه', // spoken words vs digits
      },
      offsets: {..._chipOffsets(25, 28, 31), ..._gridOffsets(38, 40, 42)},
      tolerances: const {15: 4.5, 16: 4.5, 18: 4.5, 28: 3},
    );
    semantics.dispose();
  });

  testWidgets('AptRoomsBought: the boxes', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpAptRoomsBought(tester);
    expectLayoutMatches(
      tester,
      'AptRoomsBought',
      offsets: {
        21: _chipAntreeh,
        24: _chipNish,
        36: _gridFirst,
        41: _gridSecond,
      },
      tolerances: const {11: 4.5, 12: 4.5, 14: 4.5, 24: 3},
    );
    semantics.dispose();
  });

  testWidgets('AptRoomsDone: the boxes', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpAptRoomsDone(tester);
    expectLayoutMatches(
      tester,
      'AptRoomsDone',
      // The draft's scene title, not the board's.
      pairings: const {9: 'شوف المشهد: العيلة في الصالون'},
      // Flutter measures the pill's label about 9 pt wider than the browser
      // did, so its far side moves from 147 to 159; the near side stays.
      tolerances: const {9: 12.5, 15: 6.5, 16: 6.5, 18: 6.5},
    );
    semantics.dispose();
  });

  testWidgets('PieceAffordable: the boxes', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpPieceAffordable(tester);
    expectLayoutMatches(
      tester,
      'PieceAffordable',
      pairings: const {
        10: 'قفل', // the app-wide close label; the board says «اقفل»
        34: 'اشتري النجفة مودرن بـ١٬٠٥٠ جنيه',
      },
      // The sheet's 14 pt bottom padding (the board's 11.8) and its content
      // make it 703 high, not 700: it opens 3 pt higher, and what follows
      // the header with it.
      tolerances: const {10: 4.5, 16: 3.2, 19: 3.2, 21: 3.2, 34: 3.2},
      scrim: 'قفل',
    );
    semantics.dispose();
  });

  testWidgets('RoomDonePending: the boxes', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpRoomDonePending(tester);
    expectLayoutMatches(
      tester,
      'RoomDonePending',
      pairings: const {22: 'شوف المشهد: العيلة في الصالون'},
      // The board pins its dialog 17 pt lower than the app centres it (the
      // two are the same height); «بعدين» is 63 wide there, 56 here, about
      // the same centre.
      offsets: const {22: Offset(0, -16), 24: Offset(0, -16)},
      tolerances: const {24: 3.5},
      scrim: 'قفل',
    );
    semantics.dispose();
  });
}

// The expected moves, each listed in the header: the board hard-codes where a
// chip hangs and in which order the cells fall; the app hangs a chip on the
// draft's slot and orders the grid by the draft's `order`.
const _chipAntreeh = Offset(4, -5);
const _chipNish = Offset(31, -7); // centre; 128 wide against the board's 134
const _chipNagafa = Offset(1, -41);
const _gridFirst = Offset(183, 64); // the board's first cell, the app's last
const _gridSecond = Offset(-183, 0);
const _gridThird = Offset(0, -64);

Map<int, Offset> _chipOffsets(int antreeh, int nish, int nagafa) => {
  antreeh: _chipAntreeh,
  nish: _chipNish,
  nagafa: _chipNagafa,
};

Map<int, Offset> _gridOffsets(int nish, int antreeh, int nagafa) => {
  nish: _gridFirst,
  antreeh: _gridSecond,
  nagafa: _gridThird,
};
