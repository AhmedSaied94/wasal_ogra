// Whether a start shows the pre-trip card (specs/013-m08-home-result,
// research R6): a story trip always, a trip with something new always,
// otherwise as the setting says.
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/features/pre_trip/domain/card_mode.dart';
import 'package:wassal/features/pre_trip/domain/met_set.dart';

import '../../../helpers/economy.dart';
import '../../../helpers/progress.dart';

void main() {
  final c = sampleContent();
  final everything = metSet(
    c,
    player({
      for (final t in c.lines.expand((l) => c.tripsOf(l.lineId))) t.tripId: 3,
    }),
  );

  bool show(String tripId, {required bool always, MetSet? met}) =>
      shouldShowCard(c.trip(tripId)!, met ?? everything, always: always);

  test('a story trip: always', () {
    expect(show('line_hay.03', always: false), isTrue);
  });

  test('something new: always', () {
    final met = metSet(c, player({'line_hay.01': 1}));
    // line_hay.02 brings الحاجة.
    expect(show('line_hay.02', always: false, met: met), isTrue);
  });

  test('nothing new: as the setting says', () {
    expect(show('line_hay.02', always: true), isTrue);
    expect(show('line_hay.02', always: false), isFalse);
  });
}
