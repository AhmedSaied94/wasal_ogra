// Story trips come at their moment everywhere (specs/014-m09-lines-vehicles,
// US5 scenarios 1–5, FR-007, FR-012): the grid, Home's next trip, the card
// and the start path agree, on the release draft's shape.
import 'package:content_models/content_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/routing/router.dart';
import 'package:wassal/features/home/application/start_next_trip.dart';
import 'package:wassal/features/home/domain/next_trip.dart';
import 'package:wassal/features/lines/domain/line_standing.dart';
import 'package:wassal/features/lines/domain/trip_cells.dart';
import 'package:wassal/features/lines/presentation/lines_screen.dart';
import 'package:wassal/features/pre_trip/presentation/pre_trip_card.dart';

import '../../helpers/lines.dart';
import '../../helpers/progress.dart';
import '../../helpers/synthetic_packs.dart';

String _t(String line, int n) => '$line.${n.toString().padLeft(2, '0')}';

final _hay = {for (var n = 1; n <= 19; n++) _t('line_hay', n): 1};
final _gamaa17 = {for (var n = 1; n <= 17; n++) _t('line_gamaa', n): 1};

/// The US5 states: (name, stars, owned, the line Home follows, the story
/// trip, whether it is playable).
final _states =
    <(String, Map<String, int>, Set<(SkuKind, String)>, String, String, bool)>[
      (
        '1: line_hay.01–.18 done',
        {for (var n = 1; n <= 18; n++) _t('line_hay', n): 1},
        {},
        'line_hay.18',
        'line_hay.20',
        false,
      ),
      ('2: line_hay.01–.19 done', _hay, {}, 'line_hay.19', 'line_hay.20', true),
      (
        '3: no microbus',
        {..._hay, 'line_hay.20': 1},
        {},
        'line_hay.20',
        'line_gamaa.01',
        false,
      ),
      (
        '4: .17 done, no shabka',
        {..._hay, 'line_hay.20': 1, ..._gamaa17},
        {microOld},
        'line_gamaa.17',
        'line_gamaa.18',
        false,
      ),
      (
        '5: the shabka bought',
        {..._hay, 'line_hay.20': 1, ..._gamaa17},
        {microOld, shabka},
        'line_gamaa.17',
        'line_gamaa.18',
        true,
      ),
    ];

void main() {
  final c = draftContent();

  for (final (name, stars, owned, last, story, playable) in _states) {
    test('$name: the grid and Home agree', () {
      final p = player(stars, owned);
      final storyLine = c.trip(story)!.lineId;
      final cell = tripCells(
        c,
        p,
        storyLine,
      ).firstWhere((cell) => cell.tripId == story);
      expect(cell.isStory, isTrue);
      expect(cell.startable, playable, reason: name);
      // Home's next trip on the line it follows is the grid's next trip.
      final home = nextTrip(c, p, lastFinishedTripId: last);
      final followed = c.trip(last)!.lineId;
      final next = nextInLine(c, p, followed);
      if (next != null) {
        expect(home?.tripId, next.tripId, reason: name);
        final grid = tripCells(
          c,
          p,
          followed,
        ).where((cell) => cell.state == CellState.next);
        expect(grid.single.tripId, next.tripId, reason: name);
      }
      if (!playable) expect(home?.tripId, isNot(story), reason: name);
    });
  }

  testWidgets('the card and the start path refuse a story trip that '
      'waits', (tester) async {
    final (container, _) = await pumpLinesApp(
      tester,
      pack: draftShaped(),
      state: playerState(
        stars: {..._hay, 'line_hay.20': 1, ..._gamaa17},
        owned: {microOld},
      ),
    );
    final element = tester.element(find.byType(LinesScreen));
    final started = await startNextTrip(
      element,
      element as WidgetRef,
      tripId: 'line_gamaa.18',
      from: StartFrom.lines,
    );
    await tester.pumpAndSettle();
    expect(started, isFalse);
    expect(locationOf(container), '/lines');

    container
        .read(routerProvider)
        .go('/lines/line_gamaa/pre-trip/line_gamaa.18');
    await tester.pumpAndSettle();
    expect(find.byType(PreTripCard), findsNothing);
    expect(locationOf(container), '/lines/line_gamaa');
  });
}
