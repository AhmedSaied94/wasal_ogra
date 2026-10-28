// Home's line card in figures (specs/013-m08-home-result, data-model
// `LineCardFigures`).
import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/features/home/domain/line_card.dart';
import 'package:wassal/features/home/domain/next_trip.dart';

import '../../../helpers/economy.dart';
import '../../../helpers/progress.dart';

void main() {
  final c = sampleContent();

  test("the trip's place, the trips finished and the stars", () {
    final p = player({'line_hay.01': 3, 'line_hay.02': 0, 'line_hay.03': 2});
    final next = nextTrip(c, p, lastFinishedTripId: 'line_hay.01')!;
    final figures = lineCardFigures(c, p, next)!;
    expect(figures.lineName, 'خط الحي');
    expect(figures.tripIndex, next.index);
    expect(figures.tripIndex, 2);
    expect(figures.tripTotal, c.tripsOf(LineId.lineHay).length);
    expect(figures.tripTotal, 3);
    // A failed trip, at no star, isn't finished.
    expect(figures.finished, 2);
    expect(figures.starsEarned, 5);
    expect(figures.starsMax, 9);
    expect(figures.progress, closeTo(2 / 3, 1e-9));
  });

  test('a new player: nothing yet', () {
    final next = nextTrip(c, player())!;
    final figures = lineCardFigures(c, player(), next)!;
    expect(figures.tripIndex, 1);
    expect(figures.finished, 0);
    expect(figures.starsEarned, 0);
    expect(figures.progress, 0);
  });
}
