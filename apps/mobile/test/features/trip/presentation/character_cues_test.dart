import 'dart:ui';

import 'package:content_models/content_models.dart';
import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/features/trip/application/trip_controller.dart';
import 'package:wassal/features/trip/domain/cues.dart';
import 'package:wassal/features/trip/domain/looks.dart';
import 'package:wassal/features/trip/domain/poses.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';
import 'package:wassal/features/trip/presentation/scene/passenger_art.dart';
import 'package:wassal/features/trip/presentation/scene/trip_game.dart';

import '../../../helpers/trip.dart';

// The scene plays each `CharacterCue` on its passenger's art, also when the
// cue comes before the frame that seats them; each seat makes its art with
// its row, and again when the factory changes (tasks.md T106,
// contracts/rive-characters.md "Triggers").

final class _Art implements PassengerArt {
  _Art(this.row);

  final SeatRow row;
  final played = <CharacterTrigger>[];
  String? passengerId;

  @override
  bool reduceMotion = false;

  @override
  void update(PassengerView view) => passengerId = view.passengerId;

  @override
  void play(CharacterTrigger trigger) => played.add(trigger);

  @override
  void advance(double dt) {}

  @override
  void render(Canvas canvas, Rect box) {}

  @override
  void dispose() {}
}

final class _Factory implements PassengerArtFactory {
  final made = <_Art>[];

  @override
  PassengerArt create(
    Look look, {
    SeatRow row = SeatRow.a,
    bool reduceMotion = false,
  }) {
    final art = _Art(row);
    made.add(art);
    return art;
  }

  _Art of(String passengerId) =>
      made.lastWhere((art) => art.passengerId == passengerId);
}

TripGame _game(WidgetTester tester) => tester
    .widget<GameWidget<TripGame>>(find.byType(GameWidget<TripGame>))
    .game!;

Future<(TripController, _Factory)> _open(WidgetTester tester) async {
  final fixture = loadFixture('event__roadside_pickup');
  await pumpTrip(
    tester,
    tripId: fixture.definition.tripId,
    fixed: FixedTrip(
      definition: fixture.definition,
      params: fixture.params,
      seed: fixture.seed,
    ),
  );
  final factory = _Factory();
  // The scene steps only on a change in tests: step it once to seat the
  // passengers with the new factory.
  _game(tester)
    ..art = factory
    ..stepEngine(stepTime: 0);
  await tester.pump();
  return (controllerOf(tester), factory);
}

void main() {
  testWidgets('a new factory makes every seated passenger again, by row', (
    tester,
  ) async {
    final (c, factory) = await _open(tester);
    final seated = c.view!.passengers.where(
      (p) => p.presence != PresenceView.gone,
    );
    expect(seated, isNotEmpty);
    final seats = {
      for (final seat in c.session!.facts.definition.seats) seat.seatId: seat,
    };
    for (final p in seated) {
      expect(factory.of(p.passengerId).row, seats[p.seatId]!.row);
    }
  });

  testWidgets('boarding plays board on the new passenger', (tester) async {
    final (c, factory) = await _open(tester);
    await untilView(
      tester,
      c,
      (v) => v.passenger('p2')?.presence == PresenceView.aboard,
    );
    expect(factory.of('p2').played, contains(CharacterTrigger.board));
  });

  testWidgets('a cue plays on the seated passenger it names', (tester) async {
    final (c, factory) = await _open(tester);
    final id = c.view!.passengers.first.passengerId;
    _game(tester).stage.onCue(CharacterCue(id, CharacterTrigger.targeted));
    expect(factory.of(id).played, [CharacterTrigger.targeted]);
  });

  testWidgets('a cue for someone not seated yet waits for their art', (
    tester,
  ) async {
    await _open(tester);
    final stage = _game(tester).stage
      ..onCue(const CharacterCue('later', CharacterTrigger.board))
      ..onCue(const CharacterCue('later', CharacterTrigger.call));
    expect(stage.takeTriggers('later'), [
      CharacterTrigger.board,
      CharacterTrigger.call,
    ]);
    expect(stage.takeTriggers('later'), isEmpty);
  });
}
