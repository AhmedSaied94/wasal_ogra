import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/design/token_generator.dart';
import 'boxes.dart';
import 'c_trip_check.dart';
import 'samples/c_trip.dart';

// The checks catch drift between the app and the design (tasks.md T112,
// spec US7): a box moved or removed in the design fails the layout test,
// and a token changed in tokens.json changes exactly its generated lines.

/// `C-Trip`'s boxes, with [edit] applied to the decoded file.
DesignBoard _cTrip(void Function(List<Map<String, Object?>> boxes) edit) {
  final root = jsonDecode(
    File('../../docs/design/boxes/C-Trip.json').readAsStringSync(),
  ) as Map<String, Object?>;
  final boxes = [
    for (final box in root['boxes']! as List<Object?>)
      Map<String, Object?>.of(box! as Map<String, Object?>),
  ];
  edit(boxes);
  return parseBoard(jsonEncode({...root, 'boxes': boxes}), artboard: 'C-Trip');
}

/// The message of the layout check over [board].
Future<String> _failure(WidgetTester tester, DesignBoard board) async {
  final semantics = tester.ensureSemantics();
  await pumpCTrip(tester);
  try {
    expectCTripLayout(tester, board: board);
  } on TestFailure catch (failure) {
    return failure.message ?? '';
  } finally {
    semantics.dispose();
  }
  fail('The layout check passed over a changed board.');
}

void main() {
  testWidgets('box 1 (pause) moved 3 pt: the check fails naming it', (
    tester,
  ) async {
    final board = _cTrip((boxes) {
      final pause = boxes.singleWhere((b) => b['id'] == 1);
      pause['x'] = (pause['x']! as num) + 3;
    });
    final message = await _failure(tester, board);
    expect(message, contains('box 1 "إيقاف مؤقت"'));
    expect(message, contains('tolerance ±2'));
  });

  testWidgets('box 1 removed: the pause button matches no box', (tester) async {
    final board = _cTrip((boxes) => boxes.removeWhere((b) => b['id'] == 1));
    final message = await _failure(tester, board);
    expect(message, contains('"إيقاف مؤقت"'));
    expect(message, contains('matches no box'));
  });

  test('color.primary changed: only the primary lines move', () {
    final json = jsonDecode(
      File('../../docs/design/tokens.json').readAsStringSync(),
    ) as Map<String, Object?>;
    final color = Map<String, Object?>.of(
      json['color']! as Map<String, Object?>,
    )..['primary'] = '#123456';
    final changed = formatTokens(generateTokens({...json, 'color': color}))
        .split('\n');
    final committed = formatTokens(
      File('lib/core/theme/tokens/design_tokens.dart').readAsStringSync(),
    ).split('\n');
    expect(changed, hasLength(committed.length));
    final moved = [
      for (var i = 0; i < committed.length; i++)
        if (changed[i] != committed[i]) (was: committed[i], now: changed[i]),
    ];
    expect(moved, isNotEmpty);
    for (final line in moved) {
      expect(line.was, contains('primary'), reason: line.was);
      expect(line.now, contains('0xFF123456'), reason: line.now);
    }
  });
}
