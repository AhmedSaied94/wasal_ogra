import 'package:flutter_test/flutter_test.dart';

import 'design_check.dart';
import 'samples/story_states.dart';

// The story's boards of 2026-10-31 against their measured boxes
// (specs/015-m10-apartment-story, T132). Every tap box is matched within 2 pt.
// The samples play the release draft, whose copy wins over the boards'
// (owner decision 2026-10-31), so a few labels differ and no box moves:
// - ChaptersGoal: a done row's «شوف المشهد» replays the chapter's scenes,
//   named in its label by the last one the player has unlocked: the draft's
//   «أول نظرة» (chapter 1) and «أبوها بيسأل» (chapter 2), where the board
//   says «سلمى في الموقف» and «بتشتغل إيه؟»; the current card's line is the
//   draft's, not «شبكة تليق بسلمى»;
// - RequestsEmpty: «اقفل» is the app-wide «قفل»;
// - HomeStoryEnd: as `C-Home` (the garage is phase 2; the fuel label rounds
//   to minutes; the dot reads «جديد»; the BONAT pill follows the fuel pill,
//   which Flutter's digits make wider, so it gets 4 pt). The start button's
//   label is the app's «هيصرف لتر بنزين», the same as on `C-Home`, where the
//   board's says «بيصرف»; an open question for the designer.

void main() {
  testWidgets('ChaptersGoal: the boxes', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpChaptersGoal(tester);
    expectLayoutMatches(
      tester,
      'ChaptersGoal',
      pairings: const {
        15: 'شوف المشهد: أول نظرة',
        23: 'شوف المشهد: أبوها بيسأل',
      },
    );
    semantics.dispose();
  });

  testWidgets('RequestsEmpty: the boxes', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpRequestsEmpty(tester);
    expectLayoutMatches(
      tester,
      'RequestsEmpty',
      pairings: const {11: 'قفل'},
      scrim: 'قفل',
    );
    semantics.dispose();
  });

  testWidgets('HomeStoryEnd: the boxes', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpHomeStoryEnd(tester);
    expectLayoutMatches(
      tester,
      'HomeStoryEnd',
      skip: const {16: 'the garage is phase 2 (FR-008)'},
      pairings: const {
        10: 'البنزين ٤ من ٥، اللتر الجاي بعد ١٣ دقيقة',
        47: 'يلا نطلع!، هيصرف لتر بنزين',
        55: 'حصّالة الصبح',
        67: 'الشقة، جديد',
      },
      tolerances: const {8: 4},
      appOnly: const {'لوحة التجربة'},
    );
    semantics.dispose();
  });
}
