import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/core/l10n/number_formatter.dart';
import 'package:wassal/features/trip/application/trip_controller.dart';
import 'package:wassal/features/trip/application/trip_phase.dart';
import 'package:wassal/features/trip/domain/step_accumulator.dart';
import 'package:wassal/features/trip/presentation/cards/failure_card.dart';
import 'package:wassal/features/trip/presentation/overlays/story_strip.dart';
import 'package:wassal/features/trip/presentation/top_bar/top_bar.dart';

import '../../../helpers/economy.dart';
import '../../../helpers/pump_app.dart';
import '../../../helpers/trip.dart';

// The failure card and the story strip (tasks.md T084, FR-039–FR-041,
// ux-spec «فشل المشوار»).

const _numbers = NumberFormatter(DigitStyle.arabicIndic);

final int _price = sampleContent().price(SkuKind.revive, 'revive')!.amount;

/// Opens [fixture]'s trip on an economy with [bonat] and runs it to the
/// failure.
Future<TripController> failOnScreen(
  WidgetTester tester, {
  int bonat = 0,
  String fixture = 'ending__failed',
}) async {
  final f = loadFixture(fixture);
  await pumpTrip(
    tester,
    tripId: f.definition.tripId,
    economy: await stockedEconomy(bonat: bonat),
    fixed: FixedTrip(definition: f.definition, params: f.params, seed: f.seed),
  );
  final c = controllerOf(tester);
  while (c.phase == TripPhase.running) {
    c.advance(const Duration(milliseconds: engineStepMs));
  }
  await tester.pumpAndSettle();
  return c;
}

Finder inCard(String text) =>
    find.descendant(of: find.byType(FailureCard), matching: find.text(text));

void main() {
  testWidgets('every face frowns, and the card says why', (tester) async {
    final c = await failOnScreen(tester);
    expect(c.phase, TripPhase.failed);
    expect(c.view!.passengers.every((p) => p.mood == 3), isTrue);
    expect(inCard('المشوار باظ'), findsOneWidget);
    expect(inCard('${_numbers.integer(4)} خناقات'), findsOneWidget);
    expect(inCard('عيد المشوار'), findsOneWidget);
    expect(inCard('${_numbers.integer(-1)} بنزين'), findsOneWidget);
    expect(inCard('ارجع الموقف'), findsOneWidget);
  });

  testWidgets('the revive at its price revives the trip', (tester) async {
    final c = await failOnScreen(tester, bonat: _price);
    expect(inCard('صالح بـ${_numbers.integer(_price)} بون'), findsOneWidget);
    await tester.tap(find.byKey(FailureCard.reviveKey));
    await tester.pumpAndSettle();
    expect(c.engine!.state.revived, isTrue);
    expect(c.phase, TripPhase.running);
    expect(find.byType(FailureCard), findsNothing);
  });

  testWidgets('short of its price, it says what is missing and waits', (
    tester,
  ) async {
    final c = await failOnScreen(tester, bonat: _price - 1);
    expect(inCard('صالح بـ${_numbers.integer(_price)} بون'), findsOneWidget);
    expect(inCard('ناقصك ${_numbers.integer(1)} بونات'), findsOneWidget);
    final semantics = tester.ensureSemantics();
    expect(
      tester.getSemantics(find.byKey(FailureCard.reviveKey)),
      isNot(matchesSemantics(isEnabled: true, hasEnabledState: true)),
    );
    semantics.dispose();
    await tester.tap(find.byKey(FailureCard.reviveKey));
    await tester.pumpAndSettle();
    expect(c.phase, TripPhase.failed);
  });

  testWidgets('no revive when none is offered', (tester) async {
    await failOnScreen(
      tester,
      bonat: _price,
      fixture: 'ending__story_fight_fails',
    );
    expect(find.byType(FailureCard), findsOneWidget);
    expect(find.byKey(FailureCard.reviveKey), findsNothing);
    expect(inCard('خناقة'), findsOneWidget);
  });

  testWidgets('«ارجع الموقف» goes Home', (tester) async {
    await failOnScreen(tester);
    await tester.tap(inCard('ارجع الموقف'));
    await tester.pumpAndSettle();
    expect(currentLocation(tester), '/home');
  });

  testWidgets('«عيد المشوار» starts it again', (tester) async {
    final c = await failOnScreen(tester);
    await tester.tap(find.byKey(FailureCard.restartKey));
    await tester.pumpAndSettle();
    expect(find.byType(FailureCard), findsNothing);
    expect(c.phase, TripPhase.running);
    expect(c.engine!.state.tMs, 0);
  });

  group('the story strip', () {
    testWidgets('shows under the station strip for the whole trip', (
      tester,
    ) async {
      final f = loadFixture('ending__story_fight_fails');
      await pumpTrip(
        tester,
        tripId: f.definition.tripId,
        fixed: FixedTrip(
          definition: f.definition,
          params: f.params,
          seed: f.seed,
        ),
      );
      final strip = find.text('أي خناقة والمشوار يتعاد');
      expect(strip, findsOneWidget);
      final bar = tester.getRect(find.byType(TripTopBar));
      final rect = tester.getRect(find.byType(StoryStrip));
      expect(rect.top, greaterThanOrEqualTo(bar.bottom));
      expect(rect.top - bar.bottom, lessThan(24));

      final c = controllerOf(tester);
      advanceMs(c, 10000);
      await tester.pump();
      expect(strip, findsOneWidget);
    });

    testWidgets('a regular trip has none', (tester) async {
      await pumpTrip(tester);
      expect(find.text('أي خناقة والمشوار يتعاد'), findsNothing);
    });
  });
}
