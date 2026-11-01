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
import 'apt_states.dart' show hayTrips;
import 'c_home.dart' show pumpCHome;

// `ChaptersGoal`, `RequestsEmpty` and `HomeStoryEnd` as the boards of
// 2026-10-31 draw them (specs/015-m10-apartment-story, T132). Like
// `apt_states.dart`, they play the release draft: its chapters, its scenes'
// titles, its requests. The draft has four chapters and the timeline board
// seven: the timeline names the three it lacks from its own strings.

const _sitara = (SkuKind.item, 'salon.sitara');
const _nagafa = (SkuKind.item, 'salon.nagafa');
const _nish = (SkuKind.item, 'salon.nish');
const _antreeh = (SkuKind.item, 'salon.antreeh');

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required String location,
  required EconomyState Function(int nowMs) state,
  required DigitStyle digits,
  required Size? size,
  required double textScale,
}) async {
  final (container, _) = await pumpLinesApp(
    tester,
    pack: releaseDraftPack(),
    digits: digits,
    textScale: textScale,
    location: location,
    settle: false,
    state: state,
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

/// `ChaptersGoal`: chapters 1 and 2 done, chapter 3 current with 2,200 of the
/// shabka's 3,600, and 4 to 7 locked.
Future<ProviderContainer> pumpChaptersGoal(
  WidgetTester tester, {
  DigitStyle digits = DigitStyle.arabicIndic,
  Size? size,
  double textScale = 1.0,
}) => _pump(
  tester,
  location: '/apartment/chapters',
  digits: digits,
  size: size,
  textScale: textScale,
  state: playerState(jenehat: 2200, stars: hayTrips(19), owned: {microOld}),
);

/// `RequestsEmpty`: the salon complete and the three requests taken, so
/// nothing is open or waiting to be taken.
Future<ProviderContainer> pumpRequestsEmpty(
  WidgetTester tester, {
  DigitStyle digits = DigitStyle.arabicIndic,
  Size? size,
  double textScale = 1.0,
}) => _pump(
  tester,
  location: '/apartment/requests',
  digits: digits,
  size: size,
  textScale: textScale,
  state: playerState(
    jenehat: 1325,
    stars: hayTrips(19),
    owned: {microOld, shabka, _sitara, _nagafa, _nish, _antreeh},
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

/// `HomeStoryEnd`: `C-Home`'s player (أحمد at level 3, 1,240 JENEHAT, 85
/// BONAT, trip 12 of 30 on خط الجامعة with 27 of 90 stars) with every chapter
/// of the draft done: the old microbus, the shabka and the four salon pieces
/// owned, so the story has no goal left.
Future<ProviderContainer> pumpHomeStoryEnd(
  WidgetTester tester, {
  DigitStyle digits = DigitStyle.arabicIndic,
  Size? size,
  double textScale = 1.0,
}) => pumpCHome(
  tester,
  digits: digits,
  size: size,
  textScale: textScale,
  editPack: (json) {
    final draft = releaseDraftPack();
    json
      ..clear()
      ..addAll(draft);
  },
  editState: (state) => state.copyWith(
    ownership: ownedOf(
      {microOld, shabka, _sitara, _nagafa, _nish, _antreeh},
      styles: const {
        'salon.sitara': 'plain',
        'salon.nagafa': 'crystal',
        'salon.nish': 'golden',
        'salon.antreeh': 'classic',
      },
    ),
    progress: {...starsOf(hayTrips(19)), ...state.progress},
    // Every scene of the draft has played: nothing waits.
    scenesSeen: const {
      'ch1_first_job': {'opening', 'first_sight', 'moallem_verdict'},
      'ch2_her_father': {'what_do_you_do', 'father_approves'},
      'ch3_shabka': {'the_fatha'},
      'ch4_salon': {'family_visit'},
    },
    requestsClaimed: {
      'req_antreeh_classic',
      'req_nagafa_crystal',
      'req_nish_golden',
    },
  ),
);
