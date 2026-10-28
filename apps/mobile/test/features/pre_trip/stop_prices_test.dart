import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/components/station_tag.dart';
import 'package:wassal/features/pre_trip/domain/briefing.dart';
import 'package:wassal/features/pre_trip/presentation/stop_prices.dart';

import '../../helpers/design_component.dart';

// The prices block (specs/013-m08-home-result FR-027, the edge case "a
// trip with four stops"): each tag beside its name while every word of
// every name fits there, as `PreTrip` draws it; otherwise every cell of
// the row stacks its tag over its name, so a name wraps between its words
// rather than inside one. Up to four stops in one row.

/// The block's width in the card on the reference phone (`PreTrip` box 13).
const _width = 358.0;

/// One line of a station's name, and of its fare (`PreTrip` boxes 17, 18).
const _nameLine = 15.6;
const _fareLine = 19.2;

/// A cell's padding and the tag (`PreTrip` boxes 15, 16).
const _pad = 8.0;
const _tag = 30.0;

List<StopPrice> _stops(List<String> names) => [
  for (final (i, name) in names.indexed)
    StopPrice(slot: i + 1, stationName: name, farePiasters: 450 + 250 * i),
];

Future<void> _pump(
  WidgetTester tester,
  List<String> names, {
  double width = _width,
  Size size = const Size(390, 844),
  double textScale = 1,
}) => pumpDesignComponent(
  tester,
  SizedBox(
    width: width,
    child: StopPrices(stops: _stops(names), ruleLines: const []),
  ),
  size: size,
  textScale: textScale,
);

Finder _inCell(int slot, Finder of) =>
    find.descendant(of: find.byKey(StopPrices.cellKey(slot)), matching: of);

Rect _tagOf(WidgetTester tester, int slot) =>
    tester.getRect(_inCell(slot, find.byType(StationTag)));

Rect _nameOf(WidgetTester tester, int slot, String name) =>
    tester.getRect(_inCell(slot, find.text(name)));

void main() {
  testWidgets('every word fits: each tag beside its name, as the board', (
    tester,
  ) async {
    const names = ['الكوبري', 'السور', 'الجامعة'];
    await _pump(tester, names);
    for (final (i, name) in names.indexed) {
      final tag = _tagOf(tester, i + 1);
      final text = _nameOf(tester, i + 1, name);
      // Right to left: the tag at the start, the name after it.
      expect(tag.left, greaterThan(text.right), reason: name);
      expect(text.height, closeTo(_nameLine, 0.5), reason: name);
      expect(
        tester.getSize(find.byKey(StopPrices.cellKey(i + 1))).height,
        closeTo(2 * _pad + _nameLine + _fareLine, 0.5),
      );
    }
  });

  testWidgets('a name of two words wraps between them, beside its tag', (
    tester,
  ) async {
    await _pump(tester, const ['الكوبري', 'الموقف الجديد', 'الجامعة']);
    final tag = _tagOf(tester, 2);
    final text = _nameOf(tester, 2, 'الموقف الجديد');
    expect(tag.left, greaterThan(text.right));
    expect(text.height, closeTo(2 * _nameLine, 1));
  });

  testWidgets('a word too long to sit beside the tag: every cell stacks, '
      'and the word stays whole', (tester) async {
    // The board's own sample: «المستشفى» runs out of its cell there.
    const names = ['الكوبري', 'المستشفى', 'الجامعة'];
    await _pump(tester, names);
    for (final (i, name) in names.indexed) {
      final tag = _tagOf(tester, i + 1);
      final text = _nameOf(tester, i + 1, name);
      expect(text.top, greaterThanOrEqualTo(tag.bottom), reason: name);
      expect(text.height, closeTo(_nameLine, 0.5), reason: name);
    }
    expect(
      tester.getSize(find.byKey(StopPrices.cellKey(1))).height,
      closeTo(2 * _pad + _tag + StopPrices.stackGap + _nameLine + _fareLine, 1),
    );
  });

  testWidgets('four stops: one row, stacked, every name whole', (tester) async {
    const names = ['الكوبري', 'الموقف', 'الجامعة', 'السور'];
    await _pump(tester, names);
    final tops = {
      for (var slot = 1; slot <= 4; slot++)
        tester.getRect(find.byKey(StopPrices.cellKey(slot))).top,
    };
    expect(tops, hasLength(1));
    for (final (i, name) in names.indexed) {
      final text = _nameOf(tester, i + 1, name);
      expect(text.top, greaterThanOrEqualTo(_tagOf(tester, i + 1).bottom));
      expect(text.height, closeTo(_nameLine, 0.5), reason: name);
    }
  });

  testWidgets('four stops on the small phone at ×1.3: one row, nothing '
      'overflows', (tester) async {
    await _pump(
      tester,
      const ['الكوبري', 'المستشفى', 'الجامعة', 'السور'],
      width: 328,
      size: const Size(360, 640),
      textScale: 1.3,
    );
    final cells = [
      for (var slot = 1; slot <= 4; slot++)
        tester.getRect(find.byKey(StopPrices.cellKey(slot))),
    ];
    expect({for (final c in cells) c.top}, hasLength(1));
    expect(tester.takeException(), isNull);
  });
}
