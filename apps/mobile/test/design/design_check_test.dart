import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'boxes.dart';
import 'design_check.dart';

// The check harness's own tests (contracts/design-checks.md "Matching a
// box").

const _board = '''
{
  "artboard": "Sample", "w": 200, "h": 200,
  "boxes": [
    {"id": 0, "tag": "div", "role": "box", "x": 0, "y": 0, "w": 200, "h": 200},
    {"id": 1, "tag": "a", "role": "tap", "x": 10, "y": 10, "w": 44, "h": 44, "label": "pause"},
    {"id": 2, "tag": "button", "role": "tap", "x": 10, "y": 100, "w": 100, "h": 50, "text": "go"},
    {"id": 3, "tag": "a", "role": "tap", "x": 150, "y": 150, "w": 40, "h": 40, "label": "prototype"},
    {"id": 4, "tag": "button", "role": "tap", "x": 120, "y": 10, "w": 60, "h": 60, "label": "design name"}
  ]
}
''';

Widget _tap(String label, Rect rect) => Positioned.fromRect(
  rect: rect,
  child: Semantics(
    button: true,
    label: label,
    onTap: () {},
    child: const SizedBox.expand(),
  ),
);

Future<void> _pump(
  WidgetTester tester, {
  Offset pauseShift = Offset.zero,
  bool extra = false,
  bool scrim = false,
}) async {
  applyDesignSurface(tester, const Size(200, 200), topInset: 0);
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.rtl,
      child: Stack(
        children: [
          if (scrim) _tap('pause', const Rect.fromLTWH(0, 0, 200, 200)),
          _tap('pause', const Rect.fromLTWH(10, 10, 44, 44).shift(pauseShift)),
          _tap('let us go', const Rect.fromLTWH(10, 100, 100, 50)),
          _tap('app name', const Rect.fromLTWH(120, 10, 60, 60)),
          if (extra) _tap('extra', const Rect.fromLTWH(150, 150, 44, 44)),
        ],
      ),
    ),
  );
}

void _check(WidgetTester tester) => expectLayoutMatches(
  tester,
  'Sample',
  board: parseBoard(_board),
  skip: {3: 'prototype navigation'},
  pairings: {4: 'app name'},
);

Matcher _failsWith(String text) => throwsA(
  isA<TestFailure>().having((e) => e.message, 'message', contains(text)),
);

void main() {
  testWidgets('matching rects pass; text boxes match by contains', (
    tester,
  ) async {
    await _pump(tester);
    _check(tester);
  });

  testWidgets('a control moved by 3 pt fails, naming box, label and rects', (
    tester,
  ) async {
    await _pump(tester, pauseShift: const Offset(3, 0));
    expect(
      () => _check(tester),
      _failsWith(
        'Sample: box 1 "pause": design (10.0, 10.0, 44.0×44.0), '
        'app (13.0, 10.0, 44.0×44.0)',
      ),
    );
  });

  testWidgets('a move of 2 pt is within the tolerance', (tester) async {
    await _pump(tester, pauseShift: const Offset(2, -2));
    _check(tester);
  });

  testWidgets("a box's own tolerance replaces the artboard's", (tester) async {
    await _pump(tester, pauseShift: const Offset(3, 0));
    expectLayoutMatches(
      tester,
      'Sample',
      board: parseBoard(_board),
      skip: {3: 'prototype navigation'},
      pairings: {4: 'app name'},
      tolerances: {1: 3},
    );
    await _pump(tester, pauseShift: const Offset(4, 0));
    expect(
      () => expectLayoutMatches(
        tester,
        'Sample',
        board: parseBoard(_board),
        skip: {3: 'prototype navigation'},
        pairings: {4: 'app name'},
        tolerances: {1: 3},
      ),
      _failsWith('(tolerance ±3.0 pt)'),
    );
  });

  testWidgets('a skipped box is not looked up', (tester) async {
    // Nothing on screen is labelled "prototype", and it still passes.
    await _pump(tester);
    expect(find.semantics.byLabel('prototype'), findsNothing);
    _check(tester);
  });

  testWidgets('a paired box is found by the paired label', (tester) async {
    await _pump(tester);
    expect(find.semantics.byLabel('design name'), findsNothing);
    _check(tester);
  });

  testWidgets('an extra button the design lacks fails', (tester) async {
    await _pump(tester, extra: true);
    expect(() => _check(tester), _failsWith('"extra"'));
  });

  testWidgets('an extra button listed as app-only passes', (tester) async {
    await _pump(tester, extra: true);
    expectLayoutMatches(
      tester,
      'Sample',
      board: parseBoard(_board),
      skip: {3: 'prototype navigation'},
      pairings: {4: 'app name'},
      appOnly: {'extra'},
    );
  });

  testWidgets("the scrim, named, is left out; the board's box is matched", (
    tester,
  ) async {
    await _pump(tester, scrim: true);
    // Two nodes share the label: the one at the box's place is the box's, and
    // the other, the scrim, is then a control the board lacks.
    expect(() => _check(tester), _failsWith('matches no box'));
    expectLayoutMatches(
      tester,
      'Sample',
      board: parseBoard(_board),
      skip: {3: 'prototype navigation'},
      pairings: {4: 'app name'},
      scrim: 'pause',
    );
  });

  testWidgets('a missing control fails', (tester) async {
    applyDesignSurface(tester, const Size(200, 200), topInset: 0);
    await tester.pumpWidget(const SizedBox());
    expect(() => _check(tester), _failsWith('found 0'));
  });

  testWidgets('applyDesignSurface sets the size and the top inset', (
    tester,
  ) async {
    applyDesignSurface(tester, const Size(390, 844), topInset: 36);
    late EdgeInsets padding;
    late Size size;
    await tester.pumpWidget(
      MediaQuery.fromView(
        view: tester.view,
        child: Builder(
          builder: (context) {
            padding = MediaQuery.viewPaddingOf(context);
            size = MediaQuery.sizeOf(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(size, const Size(390, 844));
    expect(padding.top, 36);
  });
}
