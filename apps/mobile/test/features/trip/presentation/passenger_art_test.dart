import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/theme/app_theme.dart';
import 'package:wassal/features/trip/domain/skin_looks.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';
import 'package:wassal/features/trip/presentation/scene/rive_passenger_art.dart';
import 'package:wassal/features/trip/presentation/trip_colors.dart';

// A passenger's view, as the character's view-model properties (tasks.md
// T058, contracts/rive-character.md "View-model properties").

final class _FakeInputs implements PassengerInputs {
  final looks = <({Color shirt, String accessory})>[];
  final states = <CharacterState>[];
  var alights = 0;
  var disposed = false;

  @override
  void setLook({required Color shirt, required String accessory}) =>
      looks.add((shirt: shirt, accessory: accessory));

  @override
  void setState(CharacterState state) => states.add(state);

  @override
  void alight() => alights++;

  @override
  void dispose() => disposed = true;
}

final class _FakeRig implements CharacterRig {
  var advanced = 0.0;
  final boxes = <Rect>[];
  var disposed = false;

  @override
  void advance(double dt) => advanced += dt;

  @override
  void render(Canvas canvas, Rect box) => boxes.add(box);

  @override
  void dispose() => disposed = true;
}

const _look = SkinLook(
  skin: 'hajja_black',
  shirt: Shirt.hajja,
  accessory: Accessory.glasses,
  labelKey: 'tripLookHajja',
);

PassengerView _view({
  PresenceView presence = PresenceView.aboard,
  int mood = 0,
  bool talking = false,
  bool asleep = false,
  bool waking = false,
  bool headphones = false,
  bool attentive = false,
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
  nearStopPulse: false,
  dropMeHere: false,
  ledgerBadge: null,
  outcome: null,
);

void main() {
  const tokens = WassalTokens.standard;

  test('the look is set once, from the skin', () {
    final inputs = _FakeInputs();
    final art = RivePassengerArt(
      rig: _FakeRig(),
      inputs: inputs,
      look: _look,
      tokens: tokens,
    );
    art
      ..update(_view())
      ..update(_view(mood: 2));
    expect(inputs.looks, [
      (shirt: shirtColor(tokens, Shirt.hajja), accessory: 'glasses'),
    ]);
  });

  test('every accessory has its wire name', () {
    for (final accessory in Accessory.values) {
      final inputs = _FakeInputs();
      RivePassengerArt(
        rig: _FakeRig(),
        inputs: inputs,
        look: SkinLook(
          skin: 'x',
          shirt: Shirt.plain,
          accessory: accessory,
          labelKey: passengerLabelKey,
        ),
        tokens: tokens,
      );
      expect(inputs.looks.single.accessory, accessory.name);
    }
  });

  test('mood, talking, sleep and headphones follow the view', () {
    final inputs = _FakeInputs();
    final art = RivePassengerArt(
      rig: _FakeRig(),
      inputs: inputs,
      look: _look,
      tokens: tokens,
    );
    art
      ..update(_view(mood: 3, talking: true))
      ..update(_view(asleep: true, headphones: true))
      // Waking up and taking the headphones off both show as awake, bare.
      ..update(_view(waking: true, attentive: true));
    expect(inputs.states, const [
      CharacterState(mood: 3, talking: true, asleep: false, headphones: false),
      CharacterState(mood: 0, talking: false, asleep: true, headphones: true),
      CharacterState(mood: 0, talking: false, asleep: false, headphones: false),
    ]);
  });

  test('the same state is not sent twice', () {
    final inputs = _FakeInputs();
    RivePassengerArt(
        rig: _FakeRig(),
        inputs: inputs,
        look: _look,
        tokens: tokens,
      )
      ..update(_view(mood: 1))
      ..update(_view(mood: 1));
    expect(inputs.states, hasLength(1));
  });

  test('alight fires once, when they start to leave', () {
    final inputs = _FakeInputs();
    final art = RivePassengerArt(
      rig: _FakeRig(),
      inputs: inputs,
      look: _look,
      tokens: tokens,
    )..update(_view());
    expect(inputs.alights, 0);
    art
      ..update(_view(presence: PresenceView.leaving))
      ..update(_view(presence: PresenceView.leaving, mood: 3));
    expect(inputs.alights, 1);
  });

  test('the rig draws, moves on and goes with the art', () {
    final rig = _FakeRig();
    final inputs = _FakeInputs();
    final art = RivePassengerArt(
      rig: rig,
      inputs: inputs,
      look: _look,
      tokens: tokens,
    )..advance(0.5);
    final recorder = PictureRecorder();
    art.render(Canvas(recorder), const Rect.fromLTWH(10, 20, 80, 96));
    recorder.endRecording().dispose();
    expect(rig.advanced, 0.5);
    expect(rig.boxes, [const Rect.fromLTWH(10, 20, 80, 96)]);

    art.dispose();
    expect(rig.disposed, isTrue);
    expect(inputs.disposed, isTrue);
  });
}
