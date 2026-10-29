// The line Lines opens on (specs/014-m09-lines-vehicles, data-model "The
// focus line", FR-010).
import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/progress/domain/player_progress.dart';
import 'package:wassal/features/home/domain/next_trip.dart';
import 'package:wassal/features/lines/domain/focus_line.dart';

import '../../../helpers/economy.dart';
import '../../../helpers/progress.dart';

void main() {
  test('the line of Home\'s next trip', () {
    final c = artboardContent();
    expect(
      focusLine(c, PlayerProgress.empty, NextTrip.of(c, 'line_hay.02')),
      LineId.lineHay,
    );
    // M07's tutorial trip in the first session is Home's next trip too.
    final p = player({...hayDone}, {microOld});
    expect(focusLine(c, p, NextTrip.of(c, 'line_gamaa.03')), LineId.lineGamaa);
  });

  test('with none, the last current line', () {
    final c = artboardContent();
    // The microbus bought early: line_hay and line_gamaa both current.
    final p = player({'line_hay.01': 1}, {microOld});
    expect(focusLine(c, p, null), LineId.lineGamaa);
  });

  test('else the last unlocked line', () {
    final c = artboardContent();
    final p = player({...hayDone, 'line_hay.03': 3});
    expect(focusLine(c, p, null), LineId.lineHay);
  });

  test('a next trip the pack lacks falls back', () {
    final c = sampleContent();
    expect(
      focusLine(
        c,
        PlayerProgress.empty,
        const NextTrip(
          tripId: 'line_souq.01',
          lineId: LineId.lineSouq,
          index: 1,
        ),
      ),
      LineId.lineHay,
    );
  });
}
