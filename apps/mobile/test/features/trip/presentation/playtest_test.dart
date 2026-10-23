import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/bootstrap/flavor.dart';
import 'package:wassal/core/economy/economy_providers.dart';
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/core/l10n/number_formatter.dart';
import 'package:wassal/core/routing/router.dart';
import 'package:wassal/features/trip/application/art_tier.dart';
import 'package:wassal/features/trip/application/trip_phase.dart';
import 'package:wassal/features/trip/presentation/playtest/debug_panel.dart';
import 'package:wassal/features/trip/presentation/playtest/result_summary.dart';
import 'package:wassal/features/trip/presentation/playtest/trip_list.dart';
import 'package:wassal/features/trip/presentation/top_bar/top_bar.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

import '../../../helpers/economy.dart';
import '../../../helpers/pump_app.dart';
import '../../../helpers/trip.dart';

// The playtest tools of internal builds (tasks.md T089, research R21): the
// trip list on Home, the debug panel, and the result placeholder.

const _numbers = NumberFormatter(DigitStyle.arabicIndic);

void main() {
  group('the trip list', () {
    for (final flavor in [Flavor.dev, Flavor.staging]) {
      testWidgets('on ${flavor.name}, every trip of the pack, by line', (
        tester,
      ) async {
        await pumpWassalApp(tester, flavor: flavor, initialLocation: '/home');
        final content = sampleContent();
        var trips = 0;
        for (final line in content.lines) {
          final inLine = content.tripsOf(line.lineId);
          if (inLine.isEmpty) continue;
          expect(find.text(line.name.arEg), findsWidgets);
          for (final trip in inLine) {
            expect(find.byKey(TripList.tripKey(trip.tripId)), findsOneWidget);
            trips++;
          }
        }
        expect(trips, greaterThan(0));

        final first = content.tripsOf(content.lines.first.lineId).first;
        final button = find.byKey(TripList.tripKey(first.tripId));
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(currentLocation(tester), '/trip/${first.tripId}');
      });
    }

    testWidgets('prod has none', (tester) async {
      await pumpWassalApp(
        tester,
        flavor: Flavor.prod,
        initialLocation: '/home',
      );
      expect(find.byType(TripList), findsNothing);
    });
  });

  group('the debug panel', () {
    testWidgets('pauses the trip and shows its state', (tester) async {
      final copied = clipboardOf(tester);
      await pumpTrip(tester);
      final c = controllerOf(tester);
      advanceMs(c, 2000);
      await tester.pump();

      await tester.tap(find.byKey(TripHud.debugKey));
      await tester.pumpAndSettle();
      expect(c.phase, TripPhase.paused);
      expect(c.model.pauseReason, PauseReason.debugPanel);
      final engine = c.engine!;
      final state = engine.state;
      final panel = find.byType(DebugPanel);
      expect(panel, findsOneWidget);
      for (final value in [
        engine.definition.tripId,
        '${engine.definition.rev}',
        '${engine.seed}',
        '${state.tMs} ms',
        state.status.wire,
        '${state.reputation}',
        jsonEncode(state.counters.toJson()),
      ]) {
        expect(
          find.descendant(of: panel, matching: find.text(value)),
          findsOneWidget,
          reason: value,
        );
      }

      await tester.tap(find.byKey(DebugPanel.copyKey));
      await tester.pumpAndSettle();
      expect(copied, hasLength(1));
      expect(
        jsonDecode(copied.single),
        jsonDecode(jsonEncode(engine.replayRecord.toJson())),
      );

      await tester.tap(find.byKey(DebugPanel.closeKey));
      await tester.pumpAndSettle();
      expect(find.byType(DebugPanel), findsNothing);
      expect(c.phase, TripPhase.running);
    });

    testWidgets('switches the art tier for the session, and says the file is '
        'fine', (tester) async {
      final container = await pumpTrip(tester);
      await tester.tap(find.byKey(TripHud.debugKey));
      await tester.pumpAndSettle();
      final panel = find.byType(DebugPanel);
      final l10n = lookupAppLocalizations(const Locale('ar'));
      expect(
        find.descendant(of: panel, matching: find.text(l10n.tripDebugArtFine)),
        findsOneWidget,
      );
      expect(container.read(artTierSettingProvider), ArtTier.rive);

      await tester.tap(find.byKey(DebugPanel.tierKey(ArtTier.nearRive)));
      await tester.pumpAndSettle();
      expect(container.read(artTierSettingProvider), ArtTier.nearRive);
      expect(
        find.descendant(of: panel, matching: find.text('near_rive')),
        findsOneWidget,
      );
    });

    testWidgets('is on staging too, and not on prod', (tester) async {
      await pumpTrip(tester, flavor: Flavor.staging);
      expect(find.byKey(TripHud.debugKey), findsOneWidget);
    });

    testWidgets('prod has no debug icon', (tester) async {
      await pumpTrip(tester, flavor: Flavor.prod);
      expect(find.byKey(TripHud.pauseKey), findsOneWidget);
      expect(find.byKey(TripHud.debugKey), findsNothing);
    });
  });

  group('the result placeholder', () {
    testWidgets('shows the outcome, stars and pay the trip passed', (
      tester,
    ) async {
      final container = await pumpWassalApp(tester, initialLocation: '/home');
      final result = loadFixture('ending__two_stars').expectedResult;
      container
          .read(routerProvider)
          .go('/trip/${result.tripId}/result', extra: result);
      await tester.pumpAndSettle();
      final summary = find.byType(ResultSummary);
      expect(summary, findsOneWidget);
      Finder inSummary(String text) =>
          find.descendant(of: summary, matching: find.text(text));
      expect(inSummary('وصلنا'), findsOneWidget);
      expect(
        inSummary('النجوم: ${_numbers.integer(result.stars)}'),
        findsOneWidget,
      );
      for (final (condition, label, met) in [
        ('reached', 'وصلت', result.starFlags.reached),
        ('no_fights', 'من غير خناقات', result.starFlags.noFights),
        ('no_mistakes', 'كل باقي صح من أول مرة', result.starFlags.noMistakes),
      ]) {
        expect(inSummary(label), findsOneWidget);
        expect(
          find.byKey(ResultSummary.conditionKey(condition, met: met)),
          findsOneWidget,
          reason: label,
        );
      }
      expect(
        inSummary('القبض: ${_numbers.integer(result.earningsJenehat)} جنيه'),
        findsOneWidget,
      );
    });

    testWidgets('without it, the economy\'s last result', (tester) async {
      final container = await pumpTrip(tester);
      await finishTrip(tester);
      expect(currentLocation(tester), '/trip/line_hay.01/result');
      final last = container.read(economyViewProvider).lastResult!;
      container.read(routerProvider).go('/trip/line_hay.01/result');
      await tester.pumpAndSettle();
      final summary = find.byType(ResultSummary);
      expect(
        find.descendant(of: summary, matching: find.text('وصلنا')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: summary,
          matching: find.text(
            'القبض: ${_numbers.integer(last.earningsJenehat)} جنيه',
          ),
        ),
        findsOneWidget,
      );
      expect(find.byKey(ResultSummary.starsKey), findsNothing);
    });
  });
}
