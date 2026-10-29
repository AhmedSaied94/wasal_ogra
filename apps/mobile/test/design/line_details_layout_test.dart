import 'package:flutter_test/flutter_test.dart';

import 'boxes.dart';
import 'design_check.dart';
import 'samples/line_details.dart';

// The LineDetails boards against their measured boxes
// (specs/014-m09-lines-vehicles, T046, T077, research R12). Expected
// differences: ✕ is «قفل» (M08's pairing), the cells read «خلص بـ…» and
// the story cell «…، مشوار قصة» after the state (R13), and the real Lines
// sits under the scrim.

/// The app's label for a cell the board labels «المشوار {n}، {stars}» or
/// «المشوار {n}، مشوار قصة، {stars}».
String _appLabel(String board) {
  final parts = board.split('، ');
  final story = parts.remove('مشوار قصة');
  final state = switch (parts[1]) {
    'تلات نجوم' => 'خلص بتلات نجوم',
    'نجمتين' => 'خلص بنجمتين',
    'نجمة' => 'خلص بنجمة',
    final other => other,
  };
  return [parts[0], state, if (story) 'مشوار قصة'].join('، ');
}

/// ✕ and every cell the board draws as a link, paired with the app's
/// labels.
Map<int, String> _pairings(String artboard) => {
  12: 'قفل',
  for (final box in loadBoard(artboard).taps)
    if (box.label case final label? when label.startsWith('المشوار'))
      box.id: _appLabel(label),
};

void main() {
  for (final (artboard, pump) in [
    ('LineDetails', pumpLineDetails),
    ('LineDetailsStory', pumpLineDetailsStory),
    ('LineDetailsDone', pumpLineDetailsDone),
    ('LineDetailsLocked', pumpLineDetailsLocked),
  ]) {
    testWidgets('$artboard: the boxes', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester);
      expectLayoutMatches(
        tester,
        artboard,
        pairings: _pairings(artboard),
        scrim: 'قفل',
      );
      semantics.dispose();
    });
  }
}
