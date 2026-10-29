// A line's details (specs/014-m09-lines-vehicles, contracts/line-details.md,
// US2, US4): the header, the grid from the right, the hint and the note,
// the pinned button or its absence, each cell's tap, a locked cell inert,
// a locked line, and closing four ways.
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/theme/components/overlays.dart';
import 'package:wassal/features/lines/presentation/line_details_sheet.dart';
import 'package:wassal/features/lines/presentation/trip_grid.dart';
import 'package:wassal/features/pre_trip/application/card_mode_provider.dart';
import 'package:wassal/core/config/tunable.dart';
import 'package:wassal/features/pre_trip/presentation/pre_trip_card.dart';

import '../../helpers/home.dart';
import '../../helpers/lines.dart';
import '../../helpers/memory_settings_store.dart';
import '../../helpers/progress.dart';
import '../../helpers/routing.dart';
import '../../helpers/surfaces.dart';

String _t(String line, int n) => '$line.${n.toString().padLeft(2, '0')}';

/// The `LineDetails` board's player: خط الجامعة 1–11 done, the 10th a
/// story trip, 12 next; the card always shown.
final _board = playerState(
  stars: {
    'line_hay.01': 3,
    'line_hay.02': 3,
    for (var n = 1; n <= 11; n++) _t('line_gamaa', n): n == 7 ? 1 : 2,
  },
  owned: {microOld, shabka},
);

/// The card setting on «دايمًا», so every start opens the card.
MemorySettingsStore _alwaysCard() => MemorySettingsStore({
  PreTripCardModeNotifier.key: PreTripCardMode.always.wire,
});

void main() {
  testWidgets('the header, the grid, the hint, the note and the button', (
    tester,
  ) async {
    await pumpLinesApp(tester, state: _board, location: '/lines/line_gamaa');
    expect(find.byType(LineDetailsSheet), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(LineDetailsSheet),
        matching: shows('خط الجامعة'),
      ),
      findsOneWidget,
    );
    expect(shows('٢١ من ٩٠ نجمة · ١١ مشوار خلص'), findsOneWidget);
    // Four rows of five; 21 to 30 hidden.
    expect(find.byType(TripCellView), findsNWidgets(20));
    expect(shows('والمشاوير من ٢١ لـ ٣٠ بتظهر لما تقرّب'), findsOneWidget);
    expect(find.textContaining('الجاية بتتفتح'), findsOneWidget);
    expect(shows('العب المشوار ١٢'), findsOneWidget);
    // From the right: trip 1 at the top-right, 2 to its left.
    final one = tester.getCenter(
      find.byKey(TripCellView.keyOf('line_gamaa.01')),
    );
    final two = tester.getCenter(
      find.byKey(TripCellView.keyOf('line_gamaa.02')),
    );
    final six = tester.getCenter(
      find.byKey(TripCellView.keyOf('line_gamaa.06')),
    );
    expect(two.dx, lessThan(one.dx));
    expect(six.dy, greaterThan(one.dy));
    expect(labelled('المشوار ١٢، الجاي'), findsOneWidget);
    expect(labelled('المشوار ١٠، خلص بنجمتين، مشوار قصة'), findsOneWidget);
    expect(labelled('المشوار ١٣، مقفول'), findsOneWidget);
  });

  testWidgets('a cell, a replay and the button each open the card; its '
      'close returns to the details', (tester) async {
    final (container, _) = await pumpLinesApp(
      tester,
      state: _board,
      location: '/lines/line_gamaa',
      settingsStore: _alwaysCard(),
    );
    for (final (tap, trip) in [
      (find.byKey(TripCellView.keyOf('line_gamaa.03')), 'line_gamaa.03'),
      (find.byKey(TripCellView.keyOf('line_gamaa.12')), 'line_gamaa.12'),
      (find.byKey(LineDetailsSheet.playKey), 'line_gamaa.12'),
    ]) {
      await tester.tap(tap);
      await tester.pumpAndSettle();
      expect(locationOf(container), '/lines/line_gamaa/pre-trip/$trip');
      expect(find.byType(PreTripCard), findsOneWidget);
      await tester.tap(find.byKey(PreTripCard.closeKey));
      await tester.pumpAndSettle();
      expect(locationOf(container), '/lines/line_gamaa');
    }
  });

  testWidgets('a locked cell does nothing and is no button', (tester) async {
    final (container, _) = await pumpLinesApp(
      tester,
      state: _board,
      location: '/lines/line_gamaa',
    );
    final cell = find.byKey(TripCellView.keyOf('line_gamaa.13'));
    await tester.tap(cell, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(locationOf(container), '/lines/line_gamaa');
    final node = tester.getSemantics(cell);
    expect(node.flagsCollection.isButton, isFalse);
  });

  testWidgets('a done line: every row, no hint, no button, one sentence', (
    tester,
  ) async {
    // The sample's خط الحي: three trips.
    await pumpLinesApp(
      tester,
      pack: samplePackJsonForLines(),
      state: playerState(
        stars: {'line_hay.01': 3, 'line_hay.02': 2, 'line_hay.03': 1},
      ),
      location: '/lines/line_hay',
    );
    expect(find.byType(TripCellView), findsNWidgets(3));
    expect(find.byKey(LineDetailsSheet.hintKey), findsNothing);
    expect(find.byKey(LineDetailsSheet.playKey), findsNothing);
    expect(find.textContaining('الجاية بتتفتح'), findsNothing);
  });

  testWidgets('a locked line: four rows, the reason in the button\'s place, '
      'nothing to start (US4)', (tester) async {
    final (container, _) = await pumpLinesApp(
      tester,
      location: '/lines/line_masyaf',
    );
    expect(find.byKey(LineDetailsSheet.playKey), findsNothing);
    expect(find.byKey(LineDetailsSheet.reasonKey), findsOneWidget);
    expect(labelled('الخط مقفول، بعد خط السوق'), findsOneWidget);
    expect(shows('٠ من ٦ نجوم · ٠ مشوار خلص'), findsOneWidget);
    await tester.tap(find.byKey(TripCellView.keyOf('line_masyaf.01')));
    await tester.pumpAndSettle();
    expect(locationOf(container), '/lines/line_masyaf');
  });

  group('closing', () {
    for (final (way, close) in <(String, Future<void> Function(WidgetTester))>[
      (
        '✕',
        (tester) async {
          await tester.tap(find.byKey(LineDetailsSheet.closeKey));
          await tester.pumpAndSettle();
        },
      ),
      ('back', pressBack),
      (
        'the scrim',
        (tester) async {
          await tester.tapAt(const Offset(195, 20));
          await tester.pumpAndSettle();
        },
      ),
      (
        'a swipe',
        (tester) async {
          final height = tester.getSize(find.byType(AppSheet)).height;
          await tester.drag(
            find.byKey(AppSheet.grabberKey),
            Offset(0, height * 0.4),
          );
          await tester.pumpAndSettle();
        },
      ),
    ]) {
      testWidgets(way, (tester) async {
        final (container, _) = await pumpLinesApp(
          tester,
          state: _board,
          location: '/lines/line_gamaa',
        );
        await close(tester);
        expect(locationOf(container), '/lines');
      });
    }
  });

  testWidgets('the grid scrolls above the pinned button at 1.3', (
    tester,
  ) async {
    await pumpLinesApp(
      tester,
      state: _board,
      location: '/lines/line_gamaa',
      surface: Surface.small,
      textScale: 1.3,
    );
    expect(tester.takeException(), isNull);
    final button = tester.getRect(find.byKey(LineDetailsSheet.playKey));
    final scroll = tester.getRect(find.byKey(LineDetailsSheet.scrollKey));
    expect(scroll.bottom, lessThanOrEqualTo(button.top));
  });

  testWidgets('a line the pack lacks goes to the map', (tester) async {
    final (container, _) = await pumpLinesApp(
      tester,
      pack: samplePackJsonForLines(),
      location: '/lines/line_souq',
    );
    expect(locationOf(container), '/lines');
  });
}
