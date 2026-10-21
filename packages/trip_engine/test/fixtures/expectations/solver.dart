// What the solver fixtures pin (B05 FR-013): the run the Python solver found
// for each sample trip replays to 3 stars in this engine too, with no fight,
// no mistake and no booster.
import 'package:test/test.dart';

import '../../support/fixture_io.dart';

void _threeStarsWithoutAids(Replayed run) {
  final result = resultOf(run);
  expect(result.stars, 3);
  expect(result.fights, 0);
  expect(result.mistakes, isEmpty);
  expect(result.boostersUsed, isEmpty);
  expect(result.revived, isFalse);
}

final solverExpectations = <String, Expectation>{
  'solver__line_hay_01.json': _threeStarsWithoutAids,
  'solver__line_hay_02.json': _threeStarsWithoutAids,
  'solver__line_hay_03.json': _threeStarsWithoutAids,
  'solver__line_gamaa_01.json': _threeStarsWithoutAids,
  'solver__line_gamaa_02.json': _threeStarsWithoutAids,
};
