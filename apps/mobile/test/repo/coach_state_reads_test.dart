import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Who reads a rider's money (specs/012-m07-onboarding/contracts/
// ci-checks.md "Guards"): `PassengerState.balance` and `.paidIn` are the
// engine's, read in the app only by the projection and the tutorial coach.

const _allowed = [
  'lib/features/trip/domain/projection.dart',
  'lib/features/onboarding/domain/',
];

final _reads = RegExp(r'\.(balance|paidIn)\b');

/// Each read on [lines] of [path], outside comments.
List<String> readsIn(String path, List<String> lines) => [
  for (final (i, line) in lines.indexed)
    if (!line.trimLeft().startsWith('//') && _reads.hasMatch(line))
      '$path:${i + 1}: ${line.trim()}',
];

void main() {
  test('only the projection and the coach read balance and paidIn', () {
    final found = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final path = file.path.replaceAll(r'\', '/');
      if (path.endsWith('.g.dart') || _allowed.any(path.startsWith)) continue;
      found.addAll(readsIn(path, file.readAsLinesSync()));
    }
    expect(found, isEmpty, reason: found.join('\n'));
  });

  test('the coach does read them', () {
    final coach = File('lib/features/onboarding/domain/tutorial_coach.dart');
    expect(readsIn(coach.path, coach.readAsLinesSync()), isNotEmpty);
  });

  test('the scan catches what it should', () {
    expect(readsIn('x.dart', ['final b = p.balance;']), hasLength(1));
    expect(readsIn('x.dart', ['if (p.paidIn > 0) {}']), hasLength(1));
    expect(readsIn('x.dart', ['// p.balance in a comment']), isEmpty);
    expect(readsIn('x.dart', ['final b = p.balanceOf;']), isEmpty);
  });
}
