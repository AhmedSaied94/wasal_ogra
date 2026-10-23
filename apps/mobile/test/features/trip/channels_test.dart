import 'package:flame/game.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/features/trip/application/trip_controller.dart';
import 'package:wassal/features/trip/domain/cues.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';
import 'package:wassal/features/trip/presentation/overlays/bubbles_layer.dart';
import 'package:wassal/features/trip/presentation/scene/trip_game.dart';
import 'package:wassal/features/trip/presentation/trip_screen.dart';

import '../../helpers/trip.dart';

// Every key event reaches the player on more than one channel (tasks.md
// T094, constitution XI, contracts/trip-view.md "Cues"): the same trips,
// played with sound and vibration on and then off with reduced motion,
// show the same scene and lose no word at any frame. On, the
// sounds and taps follow the cues; off, none plays, the scene never
// shakes and no bubble pops.

/// Between them, every key event of the cues table.
const _fixtures = [
  'core__short_then_topup',
  'core__fight_at_stop',
  'archetype__sleeper_missed_stop',
  'archetype__honest_returns_excess',
  'event__bump_collect_and_lose',
  'event__fare_increase',
];

/// One pumped frame: what the screen draws from, and its words.
typedef Frame = ({TripView? view, List<String> words});

/// The frames of each fixture's run with every channel on.
final _withChannels = <String, List<Frame>>{};

List<String> wordsOn(WidgetTester tester) => [
  for (final p in tester.allRenderObjects.whereType<RenderParagraph>())
    p.text.toPlainText(),
]..sort();

TripGame gameOf(WidgetTester tester) => tester
    .widget<GameWidget<TripGame>>(find.byType(GameWidget<TripGame>))
    .game!;

/// Plays [name] with the channels [on] or off (and reduced motion), and
/// returns its frames.
Future<List<Frame>> play(
  WidgetTester tester,
  String name, {
  required bool on,
  required FakeSfxPlayer sfx,
  required FakeHaptics haptics,
  List<TripCue>? cues,
}) async {
  final fixture = loadFixture(name);
  await pumpTrip(
    tester,
    tripId: fixture.definition.tripId,
    economy: await economyFor(fixture),
    fixed: FixedTrip(
      definition: fixture.definition,
      params: fixture.params,
      seed: fixture.seed,
    ),
    sfx: sfx,
    haptics: haptics,
    settingsStore: tripSettingsStore(sound: on, haptics: on),
  );
  final c = controllerOf(tester);
  final heard = c.cues.listen(cues?.add);
  addTearDown(heard.cancel);
  final frames = <Frame>[];
  final run = await ScriptedPlayer(
    tester,
    fixture,
    onFrame: () async {
      frames.add((view: c.view, words: wordsOn(tester)));
      if (!on) {
        expect(gameOf(tester).stage.position, Vector2.zero());
        expect(
          find.descendant(
            of: find.byType(SpeechBubble),
            matching: find.byType(TweenAnimationBuilder<double>),
          ),
          findsNothing,
        );
      }
    },
  ).drive();
  expect(run.result!.toJson(), fixture.expectedResult.toJson());
  return frames;
}

/// Every engine event of [name]'s replay.
List<DomainEvent> eventsOf(String name) {
  final f = loadFixture(name);
  final engine = TripEngine.start(f.definition, f.params, seed: f.seed);
  final events = <DomainEvent>[];
  for (final entry in f.commandLog) {
    while (engine.state.tMs < entry.tMs &&
        engine.status == TripStatus.running) {
      events.addAll(engine.step());
    }
    if (engine.apply(entry.command) case Accepted(events: final applied)) {
      events.addAll(applied);
    }
  }
  while (engine.status == TripStatus.running) {
    events.addAll(engine.step());
  }
  return events;
}

void main() {
  test('the trips hold every key event of the cues table', () {
    final events = [for (final name in _fixtures) ...eventsOf(name)];
    final delivered = {
      for (final e in events.whereType<ChangeDelivered>()) e.result,
    };
    final alighted = {
      for (final e in events.whereType<PassengerAlighted>()) e.outcome,
    };
    expect(events.whereType<MoneyArrivedAtDriver>(), isNotEmpty);
    expect(delivered, containsAll([ChangeResult.exact, ChangeResult.short]));
    expect(events.whereType<ExcessReturned>(), isNotEmpty);
    expect(events.whereType<StationWarning>(), isNotEmpty);
    expect(events.whereType<StationReached>(), isNotEmpty);
    expect(
      alighted,
      containsAll([AlightOutcome.fight, AlightOutcome.missedStop]),
    );
    expect(events.whereType<MoneyDropped>(), isNotEmpty);
    expect(events.whereType<DroppedLost>(), isNotEmpty);
    expect(events.whereType<FareIncreased>(), isNotEmpty);
  });

  for (final name in _fixtures) {
    testWidgets('$name with sound and vibration: they follow the cues', (
      tester,
    ) async {
      final sfx = FakeSfxPlayer();
      final haptics = FakeHaptics();
      final cues = <TripCue>[];
      _withChannels[name] = await play(
        tester,
        name,
        on: true,
        sfx: sfx,
        haptics: haptics,
        cues: cues,
      );
      expect(sfx.played, [
        for (final cue in cues.whereType<SoundCue>()) sfxOf(cue.sound),
      ]);
      expect(sfx.played, isNotEmpty);
      expect(haptics.felt, [
        for (final cue in cues.whereType<HapticCue>()) cue.kind.name,
      ]);
    });

    testWidgets('$name without them, reduced motion: the same on screen', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final sfx = FakeSfxPlayer();
      final haptics = FakeHaptics();
      final frames = await play(
        tester,
        name,
        on: false,
        sfx: sfx,
        haptics: haptics,
      );
      expect(sfx.played, isEmpty);
      expect(haptics.felt, isEmpty);
      final reference = _withChannels[name];
      expect(reference, isNotNull, reason: 'runs after the run with them');
      expect(frames.length, reference!.length);
      for (final (i, frame) in frames.indexed) {
        expect(frame.view, reference[i].view, reason: 'frame $i');
        // Nothing is lost; with motion, a switch also shows the word going
        // out (the strip's old fare) while the new one comes in.
        expect(
          reference[i].words,
          containsAll(frame.words),
          reason: 'frame $i',
        );
      }
    });
  }
}
