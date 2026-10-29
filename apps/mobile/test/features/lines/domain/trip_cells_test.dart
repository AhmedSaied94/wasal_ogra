// A line's trip grid (specs/014-m09-lines-vehicles, contracts/line-details.md
// "The cells", FR-024, FR-025).
import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/progress/domain/player_progress.dart';
import 'package:wassal/features/lines/domain/trip_cells.dart';

import '../../../helpers/economy.dart';
import '../../../helpers/progress.dart';

String _t(String line, int n) => '$line.${n.toString().padLeft(2, '0')}';

Map<String, int> get _hayRegular => {
  for (var n = 1; n <= 19; n++) _t('line_hay', n): 1,
};

/// [count] cells, the next one at [next] (none when null), those before it
/// done.
List<TripCell> _cells(int count, {int? next}) => [
  for (var n = 1; n <= count; n++)
    TripCell(
      tripId: _t('line_x', n),
      number: n,
      isStory: false,
      state: next == null
          ? CellState.done
          : n < next
          ? CellState.done
          : n == next
          ? CellState.next
          : CellState.locked,
      stars: next == null || n < next ? 1 : 0,
    ),
];

void main() {
  group('cells', () {
    test('every state, with the story chip kept', () {
      // The artboard: line_gamaa 1–11 done, 10 a story trip, 12 next,
      // 20 a story trip waiting for ch3.
      final c = artboardContent();
      final p = player(
        {
          'line_hay.01': 3,
          'line_hay.02': 3,
          for (var n = 1; n <= 11; n++) _t('line_gamaa', n): n == 7 ? 1 : 2,
        },
        {microOld},
      );
      final cells = tripCells(c, p, LineId.lineGamaa);
      expect(cells, hasLength(30));
      expect(
        cells[0],
        const TripCell(
          tripId: 'line_gamaa.01',
          number: 1,
          isStory: false,
          state: CellState.done,
          stars: 2,
        ),
      );
      expect(cells[9].isStory, isTrue);
      expect(cells[9].state, CellState.done);
      expect(cells[11].state, CellState.next);
      expect(cells[12].state, CellState.locked);
      expect(cells[19].isStory, isTrue);
      expect(cells[19].state, CellState.locked);
      expect(
        [for (final cell in cells) cell.state]
            .where((s) => s == CellState.next),
        hasLength(1),
      );
    });

    test('the next trip is past a story trip still locked before it', () {
      final c = draftContent();
      final p = player(
        {..._hayRegular, for (var n = 1; n <= 17; n++) _t('line_gamaa', n): 1},
        {microOld},
      );
      final cells = tripCells(c, p, LineId.lineGamaa);
      expect(cells[17].state, CellState.locked); // .18, before the shabka
      expect(cells[17].isStory, isTrue);
      expect(cells[18].state, CellState.next); // .19
    });

    test('a story cell that is next keeps its chip', () {
      final c = draftContent();
      final p = player(_hayRegular);
      final cells = tripCells(c, p, LineId.lineHay);
      expect(cells[19].state, CellState.next);
      expect(cells[19].isStory, isTrue);
    });

    test('after the shabka: two playable cells', () {
      final c = draftContent();
      final p = player(
        {
          ..._hayRegular,
          for (var n = 1; n <= 22; n++)
            if (n != 18) _t('line_gamaa', n): 1,
        },
        {microOld, shabka},
      );
      final cells = tripCells(c, p, LineId.lineGamaa);
      expect(cells[17].state, CellState.next);
      expect(cells[17].isStory, isTrue);
      expect(cells[22].state, CellState.playable);
      expect(cells[23].state, CellState.locked);
    });

    test('a locked line\'s cells are all locked', () {
      final cells = tripCells(
        artboardContent(),
        PlayerProgress.empty,
        LineId.lineMasyaf,
      );
      expect(cells.every((c) => c.state == CellState.locked), isTrue);
      expect(cells.every((c) => !c.startable), isTrue);
    });

    test('a line the pack lacks has none', () {
      expect(
        tripCells(sampleContent(), PlayerProgress.empty, LineId.lineSafar),
        isEmpty,
      );
    });
  });

  group('the visible range', () {
    test('by the next trip\'s row', () {
      expect(visibleRange(_cells(3, next: 1)), const VisibleRange(rows: 1));
      expect(visibleRange(_cells(20, next: 1)), const VisibleRange(rows: 4));
      expect(visibleRange(_cells(20, next: 12)), const VisibleRange(rows: 4));
      expect(visibleRange(_cells(20, next: 19)), const VisibleRange(rows: 4));
      expect(
        visibleRange(_cells(30, next: 1)),
        const VisibleRange(rows: 4, hidden: (21, 30)),
      );
      expect(
        visibleRange(_cells(30, next: 12)),
        const VisibleRange(rows: 4, hidden: (21, 30)),
      );
      expect(
        visibleRange(_cells(30, next: 19)),
        const VisibleRange(rows: 5, hidden: (26, 30)),
      );
      expect(
        visibleRange(_cells(40, next: 19)),
        const VisibleRange(rows: 5, hidden: (26, 40)),
      );
      expect(
        visibleRange(_cells(40, next: 12)),
        const VisibleRange(rows: 4, hidden: (21, 40)),
      );
    });

    test('a done line shows every row', () {
      for (final count in [3, 20, 30, 40]) {
        expect(visibleRange(_cells(count)).hidden, isNull, reason: '$count');
      }
      expect(visibleRange(_cells(40)).rows, 8);
    });

    test('a locked line shows four rows', () {
      expect(
        visibleRange(_cells(30, next: 1), locked: true),
        const VisibleRange(rows: 4, hidden: (21, 30)),
      );
      expect(
        visibleRange(_cells(3, next: 1), locked: true),
        const VisibleRange(rows: 1),
      );
    });
  });
}
