import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/check_coverage.dart';

// The coverage gate (contracts/ci-checks.md «Coverage rules»).

const fixtures = 'test/tool/fixtures';

void main() {
  final report = computeCoverage(
    lcov: File('$fixtures/coverage.lcov').readAsStringSync(),
    libDir: Directory('$fixtures/lib'),
  );

  test('files with no code to run are left out', () {
    // Dart coverage omits them, so they are not untested files.
    final files = report.files.map((f) => f.path);
    expect(files, isNot(contains('lib/core/declarations.dart')));
  });

  test('generated files and main.dart are excluded', () {
    final files = report.files.map((f) => f.path).toSet();
    expect(files, {'lib/core/a.dart', 'lib/core/untested.dart'});
  });

  test('a lib file missing from lcov counts as 0% covered', () {
    final untested = report.files.singleWhere(
      (f) => f.path == 'lib/core/untested.dart',
    );
    expect(untested.hit, 0);
    // Its executable-looking lines: the two function bodies, not the
    // comments, the import or the lone brace.
    expect(untested.found, 3);
  });

  test('the total is lines hit over lines found', () {
    expect(report.hit, 3);
    expect(report.found, 7);
    expect(report.percent, closeTo(300 / 7, 1e-9));
  });

  test('exit code: 1 below --min, 0 at or above', () async {
    Future<int> run(String min) => runGate([
      '--min',
      min,
      '--lcov',
      '$fixtures/coverage.lcov',
      '--lib',
      '$fixtures/lib',
    ], out: StringBuffer());
    expect(await run('80'), 1);
    expect(await run('42.85'), 0);
    expect(await run('${300 / 7}'), 0);
  });

  test('bad arguments exit 2', () async {
    expect(await runGate(['--min', 'lots'], out: StringBuffer()), 2);
  });
}
