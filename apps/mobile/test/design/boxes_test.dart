import 'package:flutter_test/flutter_test.dart';

import 'boxes.dart';

// The box reader (contracts/design-checks.md "Pieces").

void main() {
  test('C-Trip has 26 taps, the first being the pause button', () {
    final board = loadBoard('C-Trip');
    expect(board.w, 390);
    expect(board.h, 844);
    final taps = board.taps.toList();
    expect(taps, hasLength(26));
    final pause = taps.first;
    expect(pause.label, 'إيقاف مؤقت');
    expect((pause.x, pause.y, pause.w, pause.h), (330.0, 36.0, 44.0, 44.0));
  });

  test("Fail's first tap has no label", () {
    final first = loadBoard('Fail').taps.first;
    expect(first.label, isNull);
  });

  test('Tokens has no taps', () {
    expect(loadBoard('Tokens').taps, isEmpty);
  });

  test('a malformed file throws, naming the artboard', () {
    expect(
      () => parseBoard('{"w": 390}', artboard: 'Broken'),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('Broken'),
        ),
      ),
    );
    expect(
      () => parseBoard('not json', artboard: 'Garbled'),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('Garbled'),
        ),
      ),
    );
  });

  test('byId finds a box and names a missing one', () {
    final board = loadBoard('C-Trip');
    expect(board.byId(1).label, 'إيقاف مؤقت');
    expect(() => board.byId(99999), throwsStateError);
  });
}
