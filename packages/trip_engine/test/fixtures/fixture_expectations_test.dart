// The rule each parity fixture pins, so a wrong `fixtures.dart update` fails
// review and CI (replay-and-fixtures.md §6). Every fixture file must have an
// expectation, and every expectation a file.
import 'package:test/test.dart';

import '../support/fixture_io.dart';
import 'expectations/core.dart';
import 'expectations/us2_misc.dart';
import 'expectations/us3.dart';
import 'expectations/us4.dart';
import 'expectations/us5.dart';
import 'expectations/us6.dart';

final _expectations = <String, Expectation>{
  ...coreExpectations,
  ...us2Expectations,
  ...us3Expectations,
  ...us4Expectations,
  ...us5Expectations,
  ...us6Expectations,
  ...stressExpectations,
};

void main() {
  final files = fixtureFiles();

  test('every fixture has an expectation, and every expectation a fixture', () {
    expect(files.map(fixtureName).toSet(), _expectations.keys.toSet());
  });

  for (final file in files) {
    final name = fixtureName(file);
    group(name, () {
      test('pins its rule', () {
        final check = _expectations[name];
        if (check == null) fail('no expectation for $name');
        check(replayWithEvents(loadFixture(file)));
      });
    });
  }
}
