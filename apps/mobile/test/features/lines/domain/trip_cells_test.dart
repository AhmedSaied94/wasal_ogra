// A line's trip grid (specs/014-m09-lines-vehicles, contracts/line-details.md
// "The cells", FR-024, FR-025).
import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/content/pack_content_source.dart';
import 'package:wassal/core/progress/domain/player_progress.dart';
import 'package:wassal/features/lines/domain/trip_cells.dart';

import '../../../helpers/economy.dart';
import '../../../helpers/progress.dart';
import '../../../helpers/synthetic_packs.dart';

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

    test('a starred story trip the rules refuse keeps its stars and is no '
        'link (T097)', () {
      final c = draftContent();
      // .18 played, then the shabka purchase rolled back: ch3 is incomplete.
      final p = player(
        {..._hayRegular, for (var n = 1; n <= 18; n++) _t('line_gamaa', n): 1},
        {microOld},
      );
      final cell = tripCells(
        c,
        p,
        LineId.lineGamaa,
      ).firstWhere((cell) => cell.tripId == 'line_gamaa.18');
      expect(cell.isStory, isTrue);
      expect(cell.state, CellState.done);
      expect(cell.stars, 1);
      expect(cell.playable, isFalse);
      expect(cell.startable, isFalse);
    });

    test('a finished line a newer pack extends leaves its done story trips '
        'unplayable (T097)', () {
      final extended = draftShaped();
      final trips = extended['trips']! as List<Object?>;
      final hay = trips.cast<Map<String, Object?>>().firstWhere(
        (t) => t['trip_id'] == 'line_hay.01',
      );
      trips.add({...hay, 'trip_id': 'line_hay.21'});
      final c = PackContentSource(Pack.fromJson(extended));
      final p = player(
        {for (var n = 1; n <= 20; n++) _t('line_hay', n): 1, ..._hayRegular},
        {microOld, shabka},
      );
      final cells = tripCells(c, p, LineId.lineHay);
      final story = cells.firstWhere((cell) => cell.tripId == 'line_hay.20');
      expect(story.state, CellState.done);
      expect(story.stars, 1);
      expect(story.startable, isFalse, reason: 'ch1 needs the new trip');
      // And the line's next trip is the new one.
      expect(cells.last.tripId, 'line_hay.21');
      expect(cells.last.state, CellState.next);
    });
  });

  group('the visible range', () {
    test('a row past the furthest trip\'s, at least four', () {
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

    test('all-locked cells with no next show four rows (T108)', () {
      final lockedCells = [
        for (var n = 1; n <= 30; n++)
          TripCell(
            tripId: _t('line_x', n),
            number: n,
            isStory: false,
            state: CellState.locked,
          ),
      ];
      expect(
        visibleRange(lockedCells, locked: true),
        const VisibleRange(rows: 4, hidden: (21, 30)),
      );
    });

    test('every row through the last done, past a story trip that opened '
        'behind the player (T099)', () {
      // The draft's line_gamaa: .19–.30 played, then the shabka bought, so
      // .18 is next again. The six rows reach the finished trips.
      final cells = [
        for (var n = 1; n <= 30; n++)
          TripCell(
            tripId: _t('line_x', n),
            number: n,
            isStory: n == 18,
            state: n < 18
                ? CellState.done
                : n == 18
                ? CellState.next
                : CellState.done,
            stars: n == 18 ? 0 : 1,
          ),
      ];
      expect(visibleRange(cells), const VisibleRange(rows: 6));
      expect(visibleRange(cells).hidden, isNull);
    });

    test('one row past the furthest playable trip, not the next one '
        '(LineDetailsStory, T077)', () {
      // .19–.22 played while .18 waited for the shabka; now .18 is next and
      // .23 playable: rows through .23's fifth, and a sixth.
      List<TripCell> story(int count) => [
        for (var n = 1; n <= count; n++)
          TripCell(
            tripId: _t('line_x', n),
            number: n,
            isStory: n == 18,
            state: switch (n) {
              18 => CellState.next,
              23 => CellState.playable,
              > 23 => CellState.locked,
              _ => CellState.done,
            },
            stars: n == 18 || n >= 23 ? 0 : 3,
          ),
      ];
      expect(visibleRange(story(30)), const VisibleRange(rows: 6));
      expect(
        visibleRange(story(40)),
        const VisibleRange(rows: 6, hidden: (31, 40)),
      );
    });

    test('a line extended by a pack shows every played row (T099)', () {
      // A newer pack adds trips behind a finished player: the next trip is
      // early, but the rows reach the last one played.
      final cells = [
        for (var n = 1; n <= 40; n++)
          TripCell(
            tripId: _t('line_x', n),
            number: n,
            isStory: false,
            state: n == 12 ? CellState.next : CellState.done,
            stars: n == 12 ? 0 : 1,
          ),
      ];
      expect(visibleRange(cells), const VisibleRange(rows: 8));
    });
  });
}
