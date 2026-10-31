// The passengers in Rive (contracts/rive-characters.md "People"): per
// passenger, an instance of the file's `Person`, its `Passenger` state
// machine and its own `Passenger` view-model instance. The look is set once;
// on every view change, the inputs of the passenger's one pose; on a cue,
// its trigger. It is placed by the head's centre and scaled by the seat, as
// the static art is, which draws every seat the tier leaves out and every
// passenger under reduced motion.
import 'package:content_models/content_models.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rive/rive.dart' as rive;
import 'package:wassal/features/trip/application/art_tier.dart';
import 'package:wassal/features/trip/domain/looks.dart';
import 'package:wassal/features/trip/domain/poses.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';
import 'package:wassal/features/trip/presentation/scene/passenger_art.dart';
import 'package:wassal/core/art/rive_art.dart';
import 'package:wassal/features/trip/presentation/scene/svg_passenger_art.dart';

/// `Person`'s rig (HANDOFF §5.1): the head's centre in the artboard, and its
/// radius.
const personHead = Offset(100, 100);
const personHeadRadius = 42.0;

/// What a person's view model is set to (contracts/rive-characters.md "From
/// a pose to the inputs"): the pose's one input on and every other off, so
/// combinations the design never draws never reach the file. `headphones`
/// follows the passenger in every pose.
@immutable
final class PersonInputs {
  const PersonInputs({
    this.mood = 0,
    this.talking = false,
    this.asleep = false,
    this.headphones = false,
    this.changeDue = false,
    this.claim = false,
    this.surprised = false,
  });

  /// The inputs of [view]'s pose. A failed trip already frowns everyone
  /// through the view's mood.
  factory PersonInputs.of(PassengerView view) {
    final pose = poseFor(view, failed: false);
    return PersonInputs(
      mood: switch (pose) {
        CharacterPose.impatient1 => 1,
        CharacterPose.impatient2 => 2,
        CharacterPose.fight => 3,
        CharacterPose.angry => 4,
        _ => 0,
      },
      talking: pose == CharacterPose.talk,
      // False while waking, so the file plays `wake`.
      asleep: pose == CharacterPose.sleep && !view.waking,
      headphones: view.headphones,
      changeDue: pose == CharacterPose.changeDue,
      claim: pose == CharacterPose.claim,
      surprised: pose == CharacterPose.surprised,
    );
  }

  final int mood;
  final bool talking;
  final bool asleep;
  final bool headphones;
  final bool changeDue;
  final bool claim;
  final bool surprised;

  Map<String, bool> get booleans => {
    'talking': talking,
    'asleep': asleep,
    'headphones': headphones,
    'changeDue': changeDue,
    'claim': claim,
    'surprised': surprised,
  };

  @override
  bool operator ==(Object other) =>
      other is PersonInputs &&
      other.mood == mood &&
      other.talking == talking &&
      other.asleep == asleep &&
      other.headphones == headphones &&
      other.changeDue == changeDue &&
      other.claim == claim &&
      other.surprised == surprised;

  @override
  int get hashCode => Object.hash(
    mood,
    talking,
    asleep,
    headphones,
    changeDue,
    claim,
    surprised,
  );

  @override
  String toString() => 'PersonInputs(mood: $mood, $booleans)';
}

/// One `Person` from the file, as the art drives it: the seam the tests
/// fake, so the mapping is checked without the native runtime.
abstract interface class CharacterInstance {
  void setNumber(String property, double value);
  void setBoolean(String property, {required bool value});
  void fire(String trigger);
  void advance(double dt);

  /// Draws the artboard [scale] times its size, its head's centre on
  /// [head].
  void render(Canvas canvas, Offset head, double scale);
  void dispose();
}

final class RivePassengerArtFactory implements PassengerArtFactory {
  const RivePassengerArtFactory({
    required this.person,
    this.tier = ArtTier.rive,
    this.fallback = const SvgPassengerArtFactory(),
  });

  /// Over [file]'s `Person`, which passed the contract check.
  factory RivePassengerArtFactory.of(
    rive.File file, {
    ArtTier tier = ArtTier.rive,
  }) => RivePassengerArtFactory(person: () => _RivePerson(file), tier: tier);

  final CharacterInstance Function() person;
  final ArtTier tier;

  /// What draws the seats the tier leaves out, and reduced motion.
  final PassengerArtFactory fallback;

  @override
  PassengerArt create(
    Look look, {
    SeatRow row = SeatRow.a,
    bool reduceMotion = false,
  }) {
    if (reduceMotion || !tier.drawsRow(row)) {
      return fallback.create(look, row: row, reduceMotion: reduceMotion);
    }
    return RivePassengerArt(person(), look: look);
  }
}

/// How passengers are drawn: in Rive when [art] has a usable `Person` and
/// [tier] draws any seat with it; with each look's static art otherwise.
PassengerArtFactory passengerArtFor(RiveArt? art, ArtTier tier) =>
    switch (art) {
      RiveArt(:final file?, :final usable)
          when usable.contains('Person') && tier != ArtTier.static =>
        RivePassengerArtFactory.of(file, tier: tier),
      _ => const SvgPassengerArtFactory(),
    };

/// A passenger drawn by Rive.
final class RivePassengerArt implements PassengerArt {
  RivePassengerArt(this._person, {required Look look}) {
    _person.setNumber('look', look.rive.toDouble());
  }

  final CharacterInstance _person;
  PersonInputs? _inputs;
  bool _alighted = false;

  /// Unused: under reduced motion the static art draws instead.
  @override
  bool reduceMotion = false;

  @override
  void update(PassengerView view) {
    final inputs = PersonInputs.of(view);
    final last = _inputs;
    _inputs = inputs;
    if (inputs.mood != last?.mood) {
      _person.setNumber('mood', inputs.mood.toDouble());
    }
    final before = last?.booleans;
    for (final MapEntry(key: name, :value) in inputs.booleans.entries) {
      if (before?[name] != value) _person.setBoolean(name, value: value);
    }
    // Getting off plays from the view: the engine's event has no step of
    // its own on screen (research R16).
    if (view.presence == PresenceView.leaving && !_alighted) {
      _alighted = true;
      play(CharacterTrigger.alight);
    }
  }

  @override
  void play(CharacterTrigger trigger) => _person.fire(trigger.name);

  @override
  void surprise({required bool on}) =>
      _person.setBoolean('surprised', value: on);

  @override
  void advance(double dt) => _person.advance(dt);

  @override
  void render(Canvas canvas, Rect box) =>
      _person.render(canvas, box.center, box.width / (2 * personHeadRadius));

  @override
  void dispose() => _person.dispose();
}

final class _RivePerson implements CharacterInstance {
  factory _RivePerson(rive.File file) {
    final artboard = file.artboard('Person')!;
    final machine = artboard.stateMachine('Passenger')!;
    final model = file.defaultArtboardViewModel(artboard)!;
    final instance = model.createDefaultInstance() ?? model.createInstance()!;
    model.dispose();
    machine.bindViewModelInstance(instance);
    return _RivePerson._(artboard, machine, instance);
  }

  _RivePerson._(this._artboard, this._machine, this._instance);

  final rive.Artboard _artboard;
  final rive.StateMachine _machine;
  final rive.ViewModelInstance _instance;

  @override
  void setNumber(String property, double value) =>
      _instance.number(property)?.value = value;

  @override
  void setBoolean(String property, {required bool value}) =>
      _instance.boolean(property)?.value = value;

  @override
  void fire(String trigger) => _instance.trigger(trigger)?.trigger();

  @override
  void advance(double dt) => _machine.advanceAndApply(dt);

  @override
  void render(Canvas canvas, Offset head, double scale) {
    final left = head.dx - personHead.dx * scale;
    final top = head.dy - personHead.dy * scale;
    canvas.save();
    final renderer = rive.Renderer.make(canvas);
    try {
      renderer.align(
        rive.Fit.fill,
        Alignment.topLeft,
        rive.AABB.fromValues(
          left,
          top,
          left + _artboard.width * scale,
          top + _artboard.height * scale,
        ),
        _artboard.bounds,
        1,
      );
      _artboard.draw(renderer);
    } finally {
      renderer.dispose();
      canvas.restore();
    }
  }

  @override
  void dispose() {
    _instance.dispose();
    _machine.dispose();
    _artboard.dispose();
  }
}
