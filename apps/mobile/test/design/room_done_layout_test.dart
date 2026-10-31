import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/features/apartment/presentation/room_done_dialog.dart';

import 'design_check.dart';
import 'samples/room_done.dart';

// `RoomDone` against its measured boxes (specs/015-m10-apartment-story,
// T073): the scene button (box 18) and «بعدين» (box 20). Expected
// differences: the app's dialog is its own height (the board's is drawn
// inside a fixed frame and centred 17 pt lower than the app centres it;
// `RoomDonePending` checks the boxes with that offset), «في الطريق» sits
// under the pill's first line, the CTA's label names the scene (the draft's
// «العيلة في الصالون»), and no
// `bonat_burst` plays: the reward hasn't arrived (R6).

void main() {
  testWidgets('RoomDone: the boxes', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpRoomDone(tester);
    expectLayoutMatches(
      tester,
      'RoomDone',
      pairings: const {18: 'شوف المشهد: العيلة في الصالون', 20: 'بعدين'},
      skip: const {
        18: 'the dialog is its own height, not the board frame',
        20: 'the dialog is its own height, not the board frame',
      },
      appOnly: const {'شوف المشهد: العيلة في الصالون', 'بعدين'},
      scrim: 'قفل',
    );
    expect(find.byKey(RoomDoneDialog.ctaKey), findsOneWidget);
    semantics.dispose();
  });
}
