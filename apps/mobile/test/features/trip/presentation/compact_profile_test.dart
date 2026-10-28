import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/bootstrap/flavor.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/trip/domain/scene_layout.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';
import 'package:wassal/features/trip/presentation/cards/pause_card.dart';
import 'package:wassal/features/trip/presentation/dashboard/boosters_row.dart';
import 'package:wassal/features/trip/presentation/dashboard/dashboard.dart';
import 'package:wassal/features/trip/presentation/dashboard/hand_slot.dart';
import 'package:wassal/features/trip/presentation/dashboard/talk_log_view.dart';
import 'package:wassal/features/trip/presentation/dashboard/tray.dart';
import 'package:wassal/features/trip/presentation/top_bar/station_strip_bar.dart';
import 'package:wassal/features/trip/presentation/top_bar/top_bar.dart';

import '../../../a11y/trip_minimum_sizes_test.dart'
    show paragraphRect, paragraphsIn;
import '../../../design/samples/c_trip.dart';
import '../../../helpers/trip.dart';
import 'trip_design_test.dart' show fills, l10nOf, numbers;

// The trip screen's compact profile (specs/012-m07-onboarding,
// contracts/compact-trip-layout.md, tasks.md T091): the 72 pt HUD with
// pause and the whole strip, reputation a 6 pt line on the strip's edge
// with «تحت ٤٠٪» under 40%; the 226 pt dashboard with «آخر كلام» on one
// line over the four rows; and the trip's title in the pause card, only in
// this profile.

/// `C-Trip`'s state on [surface], on a prod build (no debug button) unless
/// [flavor] says otherwise.
Future<void> _pumpCTrip(
  WidgetTester tester, {
  TripSurface surface = TripSurface.small,
  Flavor flavor = Flavor.prod,
}) async {
  await pumpTrip(tester, tripId: cTripId, surface: surface, flavor: flavor);
  controllerOf(tester).debugShowModel(cTripModel());
  await tester.pumpAndSettle();
}

Rect _rect(WidgetTester tester, Finder finder) => tester.getRect(finder);

void main() {
  group('TripHud, compact', () {
    testWidgets('pause, then the whole strip in one 64 pt row; no title', (
      tester,
    ) async {
      await _pumpCTrip(tester);
      const surface = TripSurface.small;
      final hud = _rect(tester, find.byType(TripHud));
      expect(hud.top, surface.inset);
      expect(hud.height, compactHudHeight);

      final pause = _rect(tester, find.byKey(TripHud.pauseKey));
      final strip = _rect(tester, find.byType(StationStrip));
      expect(strip.height, stripHeight);
      expect(strip.bottom, hud.bottom);
      expect(pause.center.dy, closeTo(strip.center.dy, 0.5));
      // RTL: pause at the start (right), the strip filling the rest:
      // 360 − 16 × 2 − 44 − 8.
      expect(pause.right, surface.size.width - SpaceTokens.s16);
      expect(strip.width, 276);
      expect(strip.right, pause.left - SpaceTokens.s8);

      // Every stop's dot and label is in it.
      for (final slot in [0, 1, 2]) {
        expect(find.byKey(StationStrip.dotKey(slot)), findsOneWidget);
        expect(find.text(cTripStopName(slot)), findsOneWidget);
      }
      expect(find.byKey(TripHud.titleKey), findsNothing);
      expect(find.byType(ReputationBar), findsNothing);
      expect(find.byKey(TripHud.debugKey), findsNothing);
    });

    testWidgets('reputation: a 6 pt line on the strip card, over the track, '
        'with its label', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pumpCTrip(tester);
      final l10n = l10nOf(tester);
      final line = find.byKey(TripHud.reputationLineKey);
      final rect = _rect(tester, line);
      final strip = _rect(tester, find.byType(StationStrip));
      final track = _rect(tester, find.byKey(StationStrip.trackKey));
      expect(rect.height, 6);
      expect(rect.center.dy, closeTo(strip.top, 0.5));
      expect(rect.left, closeTo(track.left, 0.5));
      expect(rect.right, closeTo(track.right, 0.5));
      expect(fills(tester, line), contains(ColorTokens.primary));
      expect(fills(tester, line), isNot(contains(ColorTokens.danger)));
      expect(
        tester.getSemantics(line),
        matchesSemantics(
          label: l10n.tripTopBarReputation(
            numbers.integer(72),
            numbers.integer(100),
          ),
        ),
      );
      expect(find.byKey(TripHud.reputationLowKey), findsNothing);
      semantics.dispose();
    });

    testWidgets('under 40%: danger, with «تحت ٤٠٪» on the line, clear of '
        'the status bar', (tester) async {
      await _pumpCTrip(tester);
      final l10n = l10nOf(tester);
      await showTripView(tester, cTripView(reputation: 30));
      final line = find.byKey(TripHud.reputationLineKey);
      expect(fills(tester, line), contains(ColorTokens.danger));
      expect(fills(tester, line), isNot(contains(ColorTokens.primary)));

      final chip = find.byKey(TripHud.reputationLowKey);
      expect(
        find.descendant(
          of: chip,
          matching: find.text(l10n.tripReputationLow(numbers.integer(40))),
        ),
        findsOneWidget,
      );
      final at = _rect(tester, chip);
      final strip = _rect(tester, find.byType(StationStrip));
      expect(at.center.dy, closeTo(_rect(tester, line).center.dy, 0.5));
      // At the strip's end (RTL: the left).
      expect(at.left, closeTo(strip.left + SpaceTokens.s10, 0.5));
      expect(at.top, greaterThanOrEqualTo(TripSurface.small.inset));
    });

    // The release pack's line_hay has four such names. On internal builds
    // the debug button narrows the strip to 224 pt, where they can reach
    // over it: a known limit of those builds only.
    testWidgets('four long names, a raised fare and the countdown fit the '
        'strip without overlapping', (tester) async {
      await _pumpCTrip(tester);
      const names = ['المريوطية', 'الطالبية', 'السرايات', 'المستشفى'];
      for (final next in [0, 1, 2, 3]) {
        await showTripView(
          tester,
          cTripView(
            tMs: 0,
            strip: StationStripView(
              chips: [
                for (final (i, name) in names.indexed)
                  StationChip(
                    stationId: 's$i',
                    slot: i,
                    name: name,
                    farePiasters: i == next ? 1250 : 1000,
                    basePiasters: 1000,
                    atMs: (i + 1) * 30000,
                    studentIcon: false,
                    reached: i < next,
                    next: i == next,
                  ),
              ],
              vehiclePermille: 0,
              countdownMs: 38000,
              warning: true,
            ),
          ),
        );
        final card = _rect(tester, find.byType(StationStrip));
        final boxes = [
          for (final p in paragraphsIn(tester, find.byType(StationStrip)))
            paragraphRect(p),
        ];
        for (final box in boxes) {
          expect(box.left, greaterThanOrEqualTo(card.left), reason: '$box');
          expect(box.right, lessThanOrEqualTo(card.right), reason: '$box');
        }
        for (var i = 0; i < boxes.length; i++) {
          for (var j = i + 1; j < boxes.length; j++) {
            final overlap = boxes[i].intersect(boxes[j]);
            expect(
              overlap.width > 0.5 && overlap.height > 0.5,
              isFalse,
              reason: 'next $next: ${boxes[i]} and ${boxes[j]}',
            );
          }
        }
      }
    });

    testWidgets('the regular HUD keeps its title and ReputationBar', (
      tester,
    ) async {
      await _pumpCTrip(tester, surface: TripSurface.a06);
      expect(tester.getSize(find.byType(TripHud)).height, tripHudHeight);
      expect(find.byKey(TripHud.titleKey), findsOneWidget);
      expect(find.byType(ReputationBar), findsOneWidget);
      expect(find.byKey(TripHud.reputationLineKey), findsNothing);
    });
  });

  group('Dashboard, compact', () {
    testWidgets('«آخر كلام» on one line at the top, then the four rows', (
      tester,
    ) async {
      await _pumpCTrip(tester);
      final board = _rect(tester, find.byType(TripDashboard));
      expect(board.height, compactDashboardHeight);
      expect(board.bottom, TripSurface.small.size.height);

      // The newest line only, in `dashboard.text`.
      final log = find.byType(LastWordsLog);
      final texts = tester
          .widgetList<Text>(
            find.descendant(of: log, matching: find.byType(Text)),
          )
          .toList();
      expect(texts, hasLength(1));
      expect(texts.single.data, contains('خد ١٠، طالب'));
      expect(texts.single.maxLines, 1);
      expect(texts.single.style?.color, ColorTokens.dashboardText);
      expect(texts.single.style?.fontWeight, FontWeight.w600);
      final logRect = _rect(tester, log);
      expect(logRect.top - board.top, compactLogTop);
      expect(logRect.height, compactLogHeight);
      expect(
        tester.getSemantics(log),
        matchesSemantics(isLiveRegion: true, label: texts.single.data),
      );

      // 44 pt rows at 32, 80, 128 and 176, 6 under the last.
      final rows = [
        _rect(tester, find.byKey(HandSlot.slotKey)),
        _rect(tester, find.byKey(Tray.slotKey(100))),
        _rect(tester, find.byKey(Tray.slotKey(2000))),
        _rect(tester, find.byType(BoostersRow)),
      ];
      expect(rows.map((r) => r.top - board.top).toList(), [32, 80, 128, 176]);
      for (final row in rows) {
        expect(row.height, dashboardRowHeight);
      }
      expect(board.bottom - rows.last.bottom, 6);
      expect(
        _rect(tester, find.byKey(CallChangeButton.buttonKey)).top,
        rows.first.top,
      );
      // Every control in the bottom third.
      expect(
        rows.first.top,
        greaterThanOrEqualTo(TripSurface.small.size.height * 2 / 3),
      );
    });
  });

  group('the pause card', () {
    for (final (surface, shown) in [
      (TripSurface.small, true),
      (TripSurface.mid, true),
      (TripSurface.a06, false),
      (TripSurface.reference, false),
    ]) {
      testWidgets('the trip title ${shown ? 'shows' : "doesn't show"} on '
          '${surface.name}', (tester) async {
        await _pumpCTrip(tester, surface: surface);
        await tester.tap(find.byKey(TripHud.pauseKey));
        await tester.pumpAndSettle();
        expect(find.byType(PauseCard), findsOneWidget);
        final title = find.byKey(PauseCard.tripTitleKey);
        expect(title, shown ? findsOneWidget : findsNothing);
        if (!shown) return;
        final l10n = l10nOf(tester);

        expect(
          find.descendant(
            of: title,
            // The pause shows the trip's own view: its first trip.
            matching: find.text(
              l10n.tripHudTitle('خط الجامعة', numbers.integer(1)),
            ),
          ),
          findsOneWidget,
        );
        // Above the subtitle.
        expect(
          _rect(tester, title).bottom,
          lessThanOrEqualTo(
            tester.getTopLeft(find.text(l10n.pauseSubtitle)).dy,
          ),
        );
      });
    }
  });
}
