import 'dart:math' as math;

import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/l10n/number_formatter.dart';
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/features/trip/application/trip_controller.dart';
import 'package:wassal/features/trip/application/trip_phase.dart';
import 'package:wassal/features/trip/domain/presentation_memory.dart';
import 'package:wassal/features/trip/domain/scene_layout.dart';
import 'package:wassal/features/trip/domain/step_accumulator.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';
import 'package:wassal/features/trip/presentation/cards/dispute_card.dart';
import 'package:wassal/features/trip/presentation/overlays/banner.dart';
import 'package:wassal/features/trip/presentation/overlays/choices_layer.dart';
import 'package:wassal/features/trip/presentation/overlays/patches_layer.dart';
import 'package:wassal/features/trip/presentation/overlays/token_layer.dart';
import 'package:wassal/features/trip/presentation/scene/passenger_component.dart';
import 'package:wassal/features/trip/presentation/scene/trip_game.dart';
import 'package:wassal/features/trip/presentation/scene/windows_component.dart';
import 'package:wassal/features/trip/presentation/trip_motion.dart';
import 'package:wassal/features/trip/presentation/trip_scope.dart';
import 'package:wassal/features/trip/presentation/dashboard/hand_slot.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

import '../../../helpers/trip.dart';

// What the eight events show and what the player can do about them
// (tasks.md T068, spec US4, ux-spec «الأحداث»).

const _numbers = NumberFormatter(DigitStyle.arabicIndic);

List<Object?> lastCommand(TripController c) =>
    c.engine!.commandLog.last.toJson().sublist(1);

/// Opens the trip of the fixture [name] and runs it until [reached].
Future<TripController> openUntil(
  WidgetTester tester,
  String name,
  bool Function(TripView view) reached,
) async {
  final fixture = loadFixture(name);
  await pumpTrip(
    tester,
    tripId: fixture.definition.tripId,
    fixed: FixedTrip(
      definition: fixture.definition,
      params: fixture.params,
      seed: fixture.seed,
    ),
  );
  final c = controllerOf(tester);
  await untilView(tester, c, reached);
  return c;
}

TripGame gameOf(WidgetTester tester) => tester
    .widget<GameWidget<TripGame>>(find.byType(GameWidget<TripGame>))
    .game!;

Rect sceneRect(WidgetTester tester) =>
    tester.getRect(find.byType(GameWidget<TripGame>));

WindowsComponent windowsOf(WidgetTester tester) =>
    gameOf(tester).stage.children.whereType<WindowsComponent>().single;

void expectTappable(WidgetTester tester, Finder finder) {
  expect(finder, findsOneWidget);
  final size = tester.getSize(finder);
  expect(size.width, greaterThanOrEqualTo(minTouch));
  expect(size.height, greaterThanOrEqualTo(minTouch));
}

void main() {
  group('bump', () {
    testWidgets('the notes in transit fall and a tap picks one up', (
      tester,
    ) async {
      final c = await openUntil(
        tester,
        'event__bump_collect_and_lose',
        (v) => v.dropped.isNotEmpty,
      );
      final dropped = c.view!.dropped;
      expect(dropped.map((d) => d.tokenId), [1, 2]);
      // On the floor, not in transit.
      for (final note in dropped) {
        expect(find.byKey(ValueKey(note.tokenId)), findsNothing);
        expectTappable(tester, find.byKey(DroppedLayer.noteKey(note.tokenId)));
        expect(
          find.descendant(
            of: find.byKey(DroppedLayer.noteKey(note.tokenId)),
            matching: find.text(_numbers.piasters(note.amountPiasters)),
          ),
          findsOneWidget,
        );
      }
      // Inside the scene, above the dashboard's overlap.
      final scene = sceneRect(tester);
      final note = tester.getRect(find.byKey(DroppedLayer.noteKey(1)));
      expect(note.top, greaterThanOrEqualTo(scene.top));
      expect(note.bottom, lessThanOrEqualTo(scene.bottom - dashboardOverlap));

      await tester.tap(find.byKey(DroppedLayer.noteKey(1)));
      await tester.pump();
      expect(lastCommand(c), ['CollectDropped', 1]);
      expect(c.view!.dropped.map((d) => d.tokenId), [2]);
      expect(find.byKey(DroppedLayer.noteKey(1)), findsNothing);

      // The other one is lost when its time is up.
      final until = c.view!.dropped.single.untilMs;
      advanceMs(c, until - c.engine!.state.tMs + engineStepMs);
      await tester.pump();
      expect(c.view!.dropped, isEmpty);
      expect(find.byKey(DroppedLayer.noteKey(2)), findsNothing);
      expect(c.view!.log.last.kind, LogKind.lost);
    });

    for (final reduced in [false, true]) {
      testWidgets(
        reduced
            ? 'the scene stays still under reduced motion'
            : 'the scene shakes',
        (tester) async {
          tester.platformDispatcher.accessibilityFeaturesTestValue =
              FakeAccessibilityFeatures(disableAnimations: reduced);
          addTearDown(
            tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
          );
          await openUntil(
            tester,
            'event__bump_collect_and_lose',
            (v) => v.dropped.isNotEmpty,
          );
          gameOf(tester).update(0.05);
          expect(gameOf(tester).stage.position.isZero(), reduced);
        },
      );
    }
  });

  testWidgets('traffic slows the street until the next station', (
    tester,
  ) async {
    final c = await openUntil(
      tester,
      'event__traffic',
      (v) => v.windows.road == Road.traffic,
    );
    expect(windowsOf(tester).road, Road.traffic);
    expect(windowsOf(tester).speed, lessThan(TripMotion.streetSpeed));
    await untilView(tester, c, (v) => v.windows.road == Road.normal);
    expect(windowsOf(tester).speed, TripMotion.streetSpeed);
  });

  testWidgets('the open road rushes the street', (tester) async {
    final c = await openUntil(
      tester,
      'event__open_road_clamped',
      (v) => v.windows.road == Road.open,
    );
    expect(windowsOf(tester).road, Road.open);
    expect(windowsOf(tester).speed, greaterThan(TripMotion.streetSpeed));
    expect(c.phase, TripPhase.running);
  });

  testWidgets('the fare banner slides in with both fares, and the strip '
      'changes its prices', (tester) async {
    final fixture = loadFixture('event__fare_increase');
    await pumpTrip(
      tester,
      tripId: fixture.definition.tripId,
      fixed: FixedTrip(
        definition: fixture.definition,
        params: fixture.params,
        seed: fixture.seed,
      ),
    );
    final c = controllerOf(tester);
    final before = [for (final chip in c.view!.strip.chips) chip.farePiasters];
    await untilView(tester, c, (v) => v.banner != null);
    final banner = c.view!.banner!;
    expect(banner.newPiasters - banner.oldPiasters, 100);
    expect(
      [for (final chip in c.view!.strip.chips) chip.farePiasters],
      [for (final fare in before) fare + 100],
    );
    expect(
      find.text(
        'الأجرة بقت ${_numbers.piasters(banner.newPiasters)} '
        'بدل ${_numbers.piasters(banner.oldPiasters)}',
      ),
      findsOneWidget,
    );
    // 008.5 writes the strip's fares as «٨ج».
    final l10n = AppLocalizations.of(
      tester.element(find.byKey(HandSlot.slotKey)),
    );
    expect(
      find.text(
        l10n.tripStripFare(
          _numbers.piasters(c.view!.strip.chips.first.farePiasters),
        ),
      ),
      findsWidgets,
    );

    // It comes down from above the scene, then holds.
    final scene = sceneRect(tester);
    final entering = tester.getRect(find.byKey(FareBanner.bannerKey));
    expect(entering.top, lessThan(scene.top));
    advanceMs(c, TripMotion.bannerIn.inMilliseconds + engineStepMs);
    await tester.pump();
    final held = tester.getRect(find.byKey(FareBanner.bannerKey));
    expect(held.top, greaterThanOrEqualTo(scene.top));

    // And leaves.
    advanceMs(c, bannerMs);
    await tester.pump();
    expect(find.byKey(FareBanner.bannerKey), findsNothing);
  });

  testWidgets('«نزّلني هنا» turns the patch into the pulsing «هنا» star', (
    tester,
  ) async {
    final c = await openUntil(
      tester,
      'event__drop_me_here',
      (v) => v.passengers.any((p) => p.dropMeHere),
    );
    final star = find.byKey(PatchesLayer.hereKey('p1'));
    expect(star, findsOneWidget);
    expect(
      find.descendant(of: star, matching: find.text('هنا')),
      findsOneWidget,
    );
    final pulse = find.descendant(of: star, matching: find.byType(TripPulse));
    expect(pulse, findsOneWidget);
    double scale() => tester
        .widget<Transform>(
          find.descendant(of: pulse, matching: find.byType(Transform)).first,
        )
        .transform
        .getMaxScaleOnAxis();
    // On the trip clock, at the hot tag's beat (008.5 takes its timing and
    // reach from the design's motion tokens).
    double at(int tMs) =>
        1 +
        TripMotion.hotPulseAmplitude *
            (0.5 -
                0.5 *
                    math.cos(
                      tMs / TripMotion.hotPulse.inMilliseconds * 2 * math.pi,
                    ));
    for (var i = 0; i < 4; i++) {
      advanceMs(c, 330);
      await tester.pump();
      expect(scale(), closeTo(at(c.view!.tMs), 1e-6));
    }
    // Still while the trip is, so the screen settles.
    c.pause(PauseReason.button);
    await tester.pumpAndSettle();
    final paused = scale();
    await tester.pump(const Duration(seconds: 1));
    expect(scale(), paused);
  });

  group('change request', () {
    for (final (agree, label) in [(true, 'فكّله'), (false, 'معلش')]) {
      testWidgets('«$label» answers it while the trip runs', (tester) async {
        final c = await openUntil(
          tester,
          'event__change_request',
          (v) => v.choices.whereType<ChangeRequestChoice>().isNotEmpty,
        );
        final answer = find.byKey(
          ChoicesLayer.changeRequestKey('p1', agree: agree),
        );
        expectTappable(tester, answer);
        expect(
          find.descendant(of: answer, matching: find.text(label)),
          findsOneWidget,
        );
        // The note they hold out.
        expect(
          find.descendant(
            of: find.byKey(ChoicesLayer.changeRequestRowKey('p1')),
            matching: find.text(_numbers.piasters(1000)),
          ),
          findsOneWidget,
        );
        expect(c.phase, TripPhase.running);
        final tMs = c.engine!.state.tMs;
        advanceMs(c, 330);
        expect(c.engine!.state.tMs, tMs + 330);
        await tester.pump();

        await tester.tap(answer);
        await tester.pump();
        expect(lastCommand(c), ['ResolveChangeRequest', 'p1', agree]);
        expect(
          find.byKey(ChoicesLayer.changeRequestRowKey('p1')),
          findsNothing,
        );
      });
    }
  });

  testWidgets('the dispute card asks «مين اللي دفع؟» with both faces', (
    tester,
  ) async {
    final c = await openUntil(
      tester,
      'event__payment_dispute',
      (v) => v.phase == TripPhase.disputeOpen,
    );
    await tester.pump();
    expect(find.byType(DisputeCard), findsOneWidget);
    expect(find.text('مين اللي دفع؟'), findsOneWidget);
    for (final id in ['p1', 'p2']) {
      expectTappable(tester, find.byKey(DisputeCard.faceKey(id)));
    }
    // As they sit: p1 on the right (A_r), p2 in the middle (A_m), each
    // with their seat and the accusation they just made.
    final p1 = tester.getRect(find.byKey(DisputeCard.faceKey('p1')));
    final p2 = tester.getRect(find.byKey(DisputeCard.faceKey('p2')));
    expect(p1.left, greaterThan(p2.right));
    for (final seat in ['الصف الأول يمين', 'الصف الأول النص']) {
      expect(
        find.descendant(
          of: find.byType(DisputeCard),
          matching: find.text(seat),
        ),
        findsOneWidget,
      );
    }
    final said = [
      for (final b in c.view!.bubbles)
        if (b.style == BubbleStyle.fight) b.passengerId,
    ];
    expect(said, unorderedEquals(['p1', 'p2']));
    final tMs = c.engine!.state.tMs;
    advanceMs(c, 1000);
    expect(c.engine!.state.tMs, tMs);

    await tester.tap(find.byKey(DisputeCard.faceKey('p1')));
    await tester.pump();
    expect(lastCommand(c), ['ResolveDispute', 0, 'p1']);
    expect(c.phase, TripPhase.running);
    expect(find.byType(DisputeCard), findsNothing);
  });

  testWidgets('a roadside pickup waves in the window and walks in through '
      'the door', (tester) async {
    final c = await openUntil(
      tester,
      'event__roadside_pickup',
      (v) => v.passengers.any(
        (p) => p.passengerId == 'p2' && p.presence == PresenceView.boarding,
      ),
    );
    expect(windowsOf(tester).waving, isTrue);
    final seatId = c.view!.passenger('p2')!.seatId;
    final component = gameOf(tester).stage.children
        .whereType<PassengerComponent>()
        .singleWhere((p) => p.seat.seatId == seatId);
    final scene = sceneRect(tester);
    final face = SceneLayout(
      c.session!.facts.definition.seats,
      vehicle: c.session!.facts.definition.vehicleId,
      width: scene.width,
      height: scene.height,
    ).seats[seatId]!.head;
    // From the door on the right.
    expect(component.artBox!.left, greaterThan(face.left + face.width));

    advanceMs(c, walkMs);
    await tester.pump();
    expect(c.view!.passenger('p2')!.presence, PresenceView.aboard);
    expect(component.artBox!.left, closeTo(face.left, 0.01));
    advanceMs(c, waveMs);
    await tester.pump();
    expect(windowsOf(tester).waving, isFalse);
  });
}
