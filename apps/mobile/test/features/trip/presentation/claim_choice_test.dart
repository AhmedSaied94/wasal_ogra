import 'dart:convert';

import 'package:content_models/content_models.dart';
import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/features/trip/application/trip_controller.dart';
import 'package:wassal/features/trip/domain/scene_layout.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';
import 'package:wassal/features/trip/presentation/dashboard/dashboard.dart';
import 'package:wassal/features/trip/presentation/overlays/choices_layer.dart';
import 'package:wassal/features/trip/presentation/scene/trip_game.dart';

import '../../../helpers/trip.dart';

// A claim is answered under the passenger while the trip runs (tasks.md
// T057, FR-031, FR-032).

/// The last command applied, as the log writes it, without its time.
List<Object?> lastCommand(TripController c) =>
    c.engine!.commandLog.last.toJson().sublist(1);

FixedTrip fixedOf(ParityFixture fixture, {TripDefinition? definition}) =>
    FixedTrip(
      definition: definition ?? fixture.definition,
      params: fixture.params,
      seed: fixture.seed,
    );

/// The fixture's trip with p2 a false claimer too, paying at the same
/// moment as p1: two claims open together.
TripDefinition twoClaimers(ParityFixture fixture) {
  final json = jsonDecode(
    jsonEncode(fixture.definition.toJson()),
  ) as Map<String, Object?>;
  final passengers = (json['passengers']! as List<Object?>)
      .cast<Map<String, Object?>>();
  final payer = passengers.firstWhere((p) => p['passenger_id'] == 'p1');
  json['passengers'] = [
    for (final p in passengers)
      p['passenger_id'] == 'p2'
          ? {
              ...p,
              'archetype': 'false_claimer',
              'pays_at_seconds': payer['pays_at_seconds'],
            }
          : p,
  ];
  return TripDefinition.fromJson(json);
}

Future<TripController> openClaims(
  WidgetTester tester,
  FixedTrip trip, {
  int count = 1,
}) async {
  await pumpTrip(tester, tripId: trip.definition.tripId, fixed: trip);
  final c = controllerOf(tester);
  await untilView(
    tester,
    c,
    (v) => v.choices.whereType<ClaimChoice>().length >= count,
  );
  return c;
}

Rect sceneRect(WidgetTester tester) =>
    tester.getRect(find.byType(GameWidget<TripGame>));

void main() {
  final believed = loadFixture('archetype__false_claimer_believed');

  testWidgets('a claim shows two answers under the passenger', (tester) async {
    final c = await openClaims(tester, fixedOf(believed));
    final accept = find.byKey(ChoicesLayer.claimKey('p1', insist: false));
    final insist = find.byKey(ChoicesLayer.claimKey('p1', insist: true));
    expect(
      find.descendant(of: accept, matching: find.text('ماشي')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: insist, matching: find.text('لأ، ما دفعتش!')),
      findsOneWidget,
    );
    for (final answer in [accept, insist]) {
      final size = tester.getSize(answer);
      expect(size.width, greaterThanOrEqualTo(minTouch));
      expect(size.height, greaterThanOrEqualTo(minTouch));
    }

    // Under the face: across its width, lower than its middle.
    final scene = sceneRect(tester);
    final layout = SceneLayout(
      c.session!.facts.definition.seats,
      width: scene.width,
      height: scene.height,
    );
    final seatId = c.view!.passengers
        .firstWhere((p) => p.passengerId == 'p1')
        .seatId;
    final face = layout.seats[seatId]!.face;
    final row = tester.getRect(find.byKey(ChoicesLayer.rowKey('p1')));
    expect(row.left, lessThan(scene.left + face.left + face.width));
    expect(row.right, greaterThan(scene.left + face.left));
    expect(row.center.dy, greaterThan(scene.top + face.top + face.height / 2));

    // The trip keeps running.
    expect(c.phase, TripPhase.running);
    final tMs = c.engine!.state.tMs;
    advanceMs(c, 330);
    expect(c.engine!.state.tMs, tMs + 330);
  });

  testWidgets('«ماشي» accepts the claim', (tester) async {
    final c = await openClaims(tester, fixedOf(believed));
    await tester.tap(find.byKey(ChoicesLayer.claimKey('p1', insist: false)));
    await tester.pump();
    expect(lastCommand(c), ['ResolveClaim', 'p1', false]);
    expect(find.byKey(ChoicesLayer.rowKey('p1')), findsNothing);
  });

  testWidgets('«لأ، ما دفعتش!» insists', (tester) async {
    final c = await openClaims(tester, fixedOf(believed));
    await tester.tap(find.byKey(ChoicesLayer.claimKey('p1', insist: true)));
    await tester.pump();
    expect(lastCommand(c), ['ResolveClaim', 'p1', true]);
    expect(find.byKey(ChoicesLayer.rowKey('p1')), findsNothing);
  });

  for (final surface in TripSurface.values) {
    testWidgets('two claims overlap neither each other nor the dashboard '
        '(${surface.name})', (tester) async {
      final trip = fixedOf(believed, definition: twoClaimers(believed));
      await pumpTrip(
        tester,
        tripId: trip.definition.tripId,
        fixed: trip,
        surface: surface,
      );
      final c = controllerOf(tester);
      await untilView(
        tester,
        c,
        (v) => v.choices.whereType<ClaimChoice>().length == 2,
      );
      final first = tester.getRect(find.byKey(ChoicesLayer.rowKey('p1')));
      final second = tester.getRect(find.byKey(ChoicesLayer.rowKey('p2')));
      expect(first.overlaps(second), isFalse, reason: '$first $second');
      final dashboard = tester.getRect(find.byType(TripDashboard));
      final scene = sceneRect(tester);
      for (final row in [first, second]) {
        expect(row.bottom, lessThanOrEqualTo(dashboard.top));
        expect(row.top, greaterThanOrEqualTo(scene.top));
        expect(row.left, greaterThanOrEqualTo(scene.left));
        expect(row.right, lessThanOrEqualTo(scene.right));
      }
    });
  }

  testWidgets('a claim left open closes as accepted when they get off', (
    tester,
  ) async {
    final c = await openClaims(tester, fixedOf(believed));
    // p1 gets off at the last station, where the trip ends.
    for (
      var t = 0;
      t < 180000 && c.engine!.state.passenger('p1')!.presence != Presence.gone;
      t += 33
    ) {
      c.advance(const Duration(milliseconds: 33));
    }
    await tester.pump();
    expect(find.byKey(ChoicesLayer.rowKey('p1')), findsNothing);
    final state = c.engine!.state;
    expect(state.claims, isEmpty);
    final p1 = state.passenger('p1')!;
    expect(p1.claimResolved, isTrue);
    expect(p1.outcome, AlightOutcome.leftUnpaid);
  });
}
