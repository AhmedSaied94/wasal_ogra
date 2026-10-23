import 'dart:ui';

import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/features/trip/application/art_tier.dart';
import 'package:wassal/features/trip/domain/looks.dart';
import 'package:wassal/features/trip/domain/poses.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';
import 'package:wassal/core/art/rive_art.dart';
import 'package:wassal/features/trip/presentation/scene/rive_passenger_art.dart';
import 'package:wassal/features/trip/presentation/scene/svg_passenger_art.dart';

// A passenger's view, as the inputs of `Person` (tasks.md T099,
// contracts/rive-characters.md "From a pose to the inputs" and "How the app
// uses it").

/// What the art set on its instance: the properties' current values, every
/// set in order, and the triggers fired.
final class _FakePerson implements CharacterInstance {
  final values = <String, Object>{};
  final sets = <String>[];
  final fired = <String>[];
  final draws = <({Offset head, double scale})>[];
  var advanced = 0.0;
  var disposed = false;

  @override
  void setNumber(String property, double value) {
    values[property] = value;
    sets.add(property);
  }

  @override
  void setBoolean(String property, {required bool value}) {
    values[property] = value;
    sets.add(property);
  }

  @override
  void fire(String trigger) => fired.add(trigger);

  @override
  void advance(double dt) => advanced += dt;

  @override
  void render(Canvas canvas, Offset head, double scale) =>
      draws.add((head: head, scale: scale));

  @override
  void dispose() => disposed = true;

  /// The inputs as the file sees them now, `look` aside.
  Map<String, Object> get inputs => {
    for (final MapEntry(:key, :value) in values.entries)
      if (key != 'look') key: value,
  };
}

final _look = looks['hagga']!;

PassengerView _view({
  PresenceView presence = PresenceView.aboard,
  int mood = 0,
  bool talking = false,
  bool asleep = false,
  bool waking = false,
  bool headphones = false,
  bool attentive = false,
  bool nearStopPulse = false,
  bool claimOpen = false,
  AlightOutcome? outcome,
}) => PassengerView(
  passengerId: 'p1',
  seatId: 'A_r',
  presence: presence,
  look: _look,
  slot: 0,
  mood: mood,
  talking: talking,
  asleep: asleep,
  waking: waking,
  headphones: headphones,
  attentive: attentive,
  nearStopPulse: nearStopPulse,
  dropMeHere: false,
  ledgerBadge: null,
  outcome: outcome,
  claimOpen: claimOpen,
);

/// Everything off: `idle`.
const _idle = <String, Object>{
  'mood': 0.0,
  'talking': false,
  'asleep': false,
  'headphones': false,
  'changeDue': false,
  'claim': false,
  'surprised': false,
};

Map<String, Object> _with(Map<String, Object> on) => {..._idle, ...on};

(RivePassengerArt, _FakePerson) _art([Look? look]) {
  final person = _FakePerson();
  return (RivePassengerArt(person, look: look ?? _look), person);
}

void main() {
  test('the look is set once, from Look.rive', () {
    final (art, person) = _art();
    art
      ..update(_view())
      ..update(_view(mood: 2));
    expect(person.sets.where((s) => s == 'look'), hasLength(1));
    expect(person.values['look'], _look.rive.toDouble());
  });

  test('every look sets its own number', () {
    for (final look in looks.values) {
      final (_, person) = _art(look);
      expect(person.values['look'], look.rive.toDouble(), reason: look.id);
    }
  });

  group("a pose's one input, the others off", () {
    final cases = <String, (PassengerView, Map<String, Object>)>{
      'idle': (_view(), _idle),
      'talk': (_view(talking: true), _with({'talking': true})),
      'impatient_1': (_view(mood: 1), _with({'mood': 1.0})),
      'impatient_2': (_view(mood: 2), _with({'mood': 2.0})),
      'impatient_2 at mood 3': (_view(mood: 3), _with({'mood': 2.0})),
      'sleep': (_view(asleep: true), _with({'asleep': true})),
      'waking: asleep off, so the file plays wake': (
        _view(asleep: true, waking: true),
        _idle,
      ),
      'headphones': (_view(headphones: true), _with({'headphones': true})),
      'change_due': (_view(nearStopPulse: true), _with({'changeDue': true})),
      'claim': (_view(claimOpen: true), _with({'claim': true})),
      'fight': (
        _view(
          presence: PresenceView.leaving,
          outcome: AlightOutcome.fight,
          mood: 3,
        ),
        _with({'mood': 3.0}),
      ),
      'asleep and talking: only sleep': (
        _view(asleep: true, talking: true),
        _with({'asleep': true}),
      ),
      'a claim while frowning: only the claim': (
        _view(claimOpen: true, mood: 2),
        _with({'claim': true}),
      ),
    };
    for (final MapEntry(key: name, value: (view, inputs)) in cases.entries) {
      test(name, () {
        final (art, person) = _art();
        art.update(view);
        expect(person.inputs, inputs);
      });
    }
  });

  test('moving between poses clears the last one', () {
    final (art, person) = _art();
    art.update(_view(talking: true));
    expect(person.inputs, _with({'talking': true}));
    art.update(_view(mood: 2, talking: true));
    expect(person.inputs, _with({'mood': 2.0}));
    art.update(_view(claimOpen: true));
    expect(person.inputs, _with({'claim': true}));
    art.update(_view());
    expect(person.inputs, _idle);
  });

  test('the headphones follow the view in every pose', () {
    final (art, person) = _art();
    art.update(_view(headphones: true, nearStopPulse: true));
    expect(person.inputs, _with({'changeDue': true, 'headphones': true}));
    // Attentive: the view takes them off, and the file lifts them.
    art.update(_view(attentive: true));
    expect(person.values['headphones'], isFalse);
  });

  test('only what changed is set again', () {
    final (art, person) = _art();
    art.update(_view(mood: 1));
    person.sets.clear();
    art
      ..update(_view(mood: 1))
      ..update(_view(mood: 2));
    expect(person.sets, ['mood']);
  });

  test('each trigger fires once, by its name', () {
    final (art, person) = _art();
    for (final trigger in CharacterTrigger.values) {
      art.play(trigger);
    }
    expect(person.fired, ['board', 'alight', 'call', 'happy', 'targeted']);
  });

  test('alight fires once, when they start to leave', () {
    final (art, person) = _art();
    art.update(_view());
    expect(person.fired, isEmpty);
    art
      ..update(_view(presence: PresenceView.leaving))
      ..update(_view(presence: PresenceView.leaving, mood: 3));
    expect(person.fired, ['alight']);
  });

  test('drawn by the head: its centre on the box, scaled to its width', () {
    final (art, person) = _art();
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    art
      ..advance(0.5)
      ..render(canvas, const Rect.fromLTWH(10, 20, 84, 84))
      ..render(canvas, const Rect.fromLTWH(0, 0, 52.5, 52.5));
    recorder.endRecording().dispose();
    expect(person.advanced, 0.5);
    expect(person.draws, [
      (head: const Offset(52, 62), scale: 1.0),
      (head: const Offset(26.25, 26.25), scale: 0.625),
    ]);
    art.dispose();
    expect(person.disposed, isTrue);
  });

  group('which art a passenger gets', () {
    RivePassengerArtFactory factory(ArtTier tier) =>
        RivePassengerArtFactory(person: _FakePerson.new, tier: tier);

    test('Rive on every row at the rive tier', () {
      for (final row in SeatRow.values) {
        expect(
          factory(ArtTier.rive).create(_look, row: row),
          isA<RivePassengerArt>(),
          reason: row.name,
        );
      }
    });

    test('near_rive: the front seat and row A in Rive, the rest static', () {
      final tier = factory(ArtTier.nearRive);
      expect(tier.create(_look, row: SeatRow.front), isA<RivePassengerArt>());
      expect(tier.create(_look), isA<RivePassengerArt>());
      for (final row in [SeatRow.b, SeatRow.c, SeatRow.d]) {
        expect(
          tier.create(_look, row: row),
          isA<SvgPassengerArt>(),
          reason: row.name,
        );
      }
    });

    test('static: every seat static', () {
      for (final row in SeatRow.values) {
        expect(
          factory(ArtTier.static).create(_look, row: row),
          isA<SvgPassengerArt>(),
        );
      }
    });

    test('reduced motion: static, whatever the tier', () {
      expect(
        factory(ArtTier.rive).create(_look, reduceMotion: true),
        isA<SvgPassengerArt>(),
      );
    });

    test('without Person in the file, the static art', () {
      for (final art in [
        null,
        const RiveArt.none(['assets/rive/wassal.riv: missing']),
        const RiveArt(file: null, usable: {'Person'}, problems: []),
      ]) {
        expect(
          passengerArtFor(art, ArtTier.rive),
          isA<SvgPassengerArtFactory>(),
        );
      }
    });
  });
}
