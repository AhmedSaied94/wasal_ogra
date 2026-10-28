import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/theme/components/story.dart';
import 'package:wassal/features/onboarding/domain/tutorial_coach.dart';
import 'package:wassal/features/onboarding/onboarding_providers.dart';
import 'package:wassal/features/onboarding/presentation/coach_layer.dart';
import 'package:wassal/features/trip/application/trip_controller.dart';
import 'package:wassal/features/trip/application/trip_phase.dart';
import 'package:wassal/features/trip/presentation/cards/pause_card.dart';
import 'package:wassal/features/trip/presentation/dashboard/tray.dart';
import 'package:wassal/features/trip/presentation/overlays/hit_areas.dart';

import '../../../helpers/content.dart';
import '../../../helpers/economy.dart';
import '../../../helpers/routing.dart';
import '../../../helpers/trip.dart';
import '../../../helpers/tutorial_content.dart';

// The coach over the trip (specs/012-m07-onboarding/contracts/coach.md "The
// overlay"): only the hole answers, lesson 0 takes any tap, the hole follows
// its target, the step is said once and only its target is reachable, no
// motion under reduced motion, and the bubble outlives an early end.

/// Pumps [tripId] coached by [lesson], on the tutorial fixture, and runs
/// its clock until a step shows.
Future<TripController> _coached(
  WidgetTester tester, {
  String tripId = 'line_hay.02',
  int lesson = 1,
}) async {
  await pumpTrip(
    tester,
    tripId: tripId,
    economy: await testEconomy(content: tutorialContent()),
    content: contentTestOverrides(assets: tutorialBundledAssets()),
    overrides: [tutorialCoachProvider(tripId).overrideWithValue(lesson)],
  );
  final c = controllerOf(tester);
  for (var t = 0; t < 120000 && c.model.coach == null; t += 33) {
    c.advance(const Duration(milliseconds: 33));
  }
  expect(c.model.coach, isNotNull, reason: 'no step showed');
  await _settle(tester);
  return c;
}

/// The anchors report after a frame, the layer rebuilds on the next, and
/// the hole moves for 250 ms.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Finder get _mark => find.byType(CoachMark);

Rect _hole(WidgetTester tester) => tester.widget<CoachMark>(_mark).target;

Offset _cell(WidgetTester tester, int denomination) =>
    tester.getCenter(find.byKey(Tray.slotKey(denomination)));

/// The messages sent to the platform's accessibility channel.
List<Map<Object?, Object?>> _accessibility(WidgetTester tester) {
  final sent = <Map<Object?, Object?>>[];
  tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler(
    SystemChannels.accessibility,
    (message) async {
      if (message is Map<Object?, Object?>) sent.add(message);
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler(
      SystemChannels.accessibility,
      null,
    ),
  );
  return sent;
}

/// Every node a screen reader can activate.
List<SemanticsNode> _tappable(WidgetTester tester) {
  final nodes = <SemanticsNode>[];
  bool visit(SemanticsNode node) {
    if (node.getSemanticsData().hasAction(SemanticsAction.tap)) {
      nodes.add(node);
    }
    node.visitChildren(visit);
    return true;
  }

  final root = tester.binding.rootPipelineOwner;
  void collect(PipelineOwner owner) {
    owner.semanticsOwner?.rootSemanticsNode?.visitChildren(visit);
    owner.visitChildren(collect);
  }

  collect(root);
  return nodes;
}

void main() {
  testWidgets('a tap outside the hole changes nothing', (tester) async {
    final c = await _coached(tester);
    expect(c.model.coach!.target, const TrayCellTarget(100));
    await tester.tapAt(_cell(tester, 500));
    await tester.tapAt(tester.getCenter(find.byKey(HitAreas.keyOf('p1'))));
    await tester.pump();
    expect(c.view!.hand.isEmpty, isTrue);
    expect(c.phase, TripPhase.running);
    expect(c.model.coach!.target, const TrayCellTarget(100));
  });

  testWidgets('a tap inside reaches the cell, then the rider', (tester) async {
    final c = await _coached(tester);
    expect(_hole(tester), tester.getRect(find.byKey(Tray.slotKey(100))));
    for (var i = 0; i < 3; i++) {
      await tester.tapAt(_cell(tester, 100));
      await tester.pump();
    }
    expect(c.view!.hand.totalPiasters, 300);
    expect(c.model.coach!.target, const PassengerTarget('p1'));
    await _settle(tester);
    await tester.tapAt(tester.getCenter(find.byKey(HitAreas.keyOf('p1'))));
    await tester.pump();
    expect(c.view!.hand.isEmpty, isTrue);
    expect(c.model.coach, isNull);
  });

  testWidgets("lesson 0: a tap anywhere is the scrim's", (tester) async {
    final c = await _coached(tester, tripId: 'line_hay.01', lesson: 0);
    expect(c.model.coach!.endsOnAnyTap, isTrue);
    // Inside the drawer's hole too: the tap ends the step and picks nothing.
    await tester.tapAt(_cell(tester, 100));
    await tester.pump();
    expect(c.view!.hand.isEmpty, isTrue);
    expect(c.model.coach, isNull);
    await tester.pump();
    expect(_mark, findsNothing);
  });

  testWidgets('the hole follows its target after a relayout', (tester) async {
    await _coached(tester);
    final before = _hole(tester);
    tester.view.physicalSize = const Size(390, 760);
    await _settle(tester);
    final cell = tester.getRect(find.byKey(Tray.slotKey(100)));
    expect(cell, isNot(before));
    expect(_hole(tester), rectMoreOrLessEquals(cell));
  });

  testWidgets('the step is announced once, as «بلية: …», and its target '
      'focused', (tester) async {
    final semantics = tester.ensureSemantics();
    final sent = _accessibility(tester);
    final c = await _coached(tester);
    // The line changes within the step: no second announcement.
    for (var i = 0; i < 3; i++) {
      await tester.tapAt(_cell(tester, 100));
      await tester.pump();
    }
    await _settle(tester);
    expect(c.model.coach!.line, const TapRiderLine());
    final said = [
      for (final m in sent)
        if (m['type'] == 'announce')
          (m['data']! as Map<Object?, Object?>)['message']! as String,
    ];
    expect(said, hasLength(1));
    expect(said.single, startsWith('بلية: '));
    expect(sent.where((m) => m['type'] == 'focus'), isNotEmpty);
    semantics.dispose();
  });

  testWidgets('only the target can be reached', (tester) async {
    final semantics = tester.ensureSemantics();
    final c = await _coached(tester);
    expect(c.model.coach!.target, const TrayCellTarget(100));
    final tappable = _tappable(tester);
    expect(tappable, hasLength(1));
    expect(
      tappable.single.rect.size,
      tester.getSize(find.byKey(Tray.slotKey(100))),
    );
    // Its action is the cell's.
    tester.semantics.performAction(
      find.semantics.byPredicate((node) => node.id == tappable.single.id),
      SemanticsAction.tap,
    );
    await tester.pump();
    expect(c.view!.hand.totalPiasters, 100);
    semantics.dispose();
  });

  testWidgets('reduced motion: no ring beat and no hand bob', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await _coached(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(_mark, findsOneWidget);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('full motion: the ring and the hand move', (tester) async {
    await _coached(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(tester.binding.transientCallbackCount, greaterThan(0));
  });

  testWidgets('back opens the pause card; the step returns after resume', (
    tester,
  ) async {
    final c = await _coached(tester);
    final step = c.model.coach;
    await pressBack(tester);
    expect(find.byType(PauseCard), findsOneWidget);
    expect(_mark, findsNothing);
    c.resume();
    await _settle(tester);
    expect(c.model.coach, step);
    expect(_mark, findsOneWidget);
  });

  testWidgets('a step that ends early: the scrim goes at once, بلية stays his '
      'time', (tester) async {
    final c = await _coached(tester);
    expect(find.byKey(CoachLayer.bubbleKey), findsOneWidget);
    for (var i = 0; i < 3; i++) {
      await tester.tapAt(_cell(tester, 100));
      await tester.pump();
    }
    await _settle(tester);
    await tester.tapAt(tester.getCenter(find.byKey(HitAreas.keyOf('p1'))));
    await tester.pump();
    expect(c.model.coach, isNull);
    expect(_mark, findsNothing);
    expect(find.byKey(CoachLayer.bubbleKey), findsOneWidget);
    expect(find.byKey(CoachLayer.headKey), findsOneWidget);
    // The game answers again.
    await tester.tapAt(_cell(tester, 500));
    await tester.pump();
    expect(c.view!.hand.totalPiasters, 500);
    // Up for its minimum time, then gone.
    final minMs = c.session!.facts.bubbleMinMs;
    advanceMs(c, minMs);
    await tester.pump();
    expect(find.byKey(CoachLayer.bubbleKey), findsNothing);
    expect(find.byKey(CoachLayer.headKey), findsNothing);
  });
}
