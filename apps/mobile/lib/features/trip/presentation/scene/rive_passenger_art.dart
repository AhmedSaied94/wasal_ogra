// The owner's Rive character (contracts/rive-character.md): the file is
// decoded once; each passenger gets its own artboard, state machine and
// view-model instance, set from its look once and from its view on every
// change, and drawn into the seat's face like the stand-in.
import 'package:material_ui/material_ui.dart';
import 'package:rive/rive.dart' as rive;
import 'package:wassal/core/theme/app_theme.dart';
import 'package:wassal/features/trip/domain/skin_looks.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';
import 'package:wassal/features/trip/presentation/scene/passenger_art.dart';
import 'package:wassal/features/trip/presentation/trip_colors.dart';

const passengerRiveAsset = 'assets/rive/passenger.riv';
const riveArtboardName = 'Passenger';
const riveStateMachineName = 'Passenger';
const riveViewModelName = 'Passenger';

/// The character file, or null when it is missing or isn't the contract's,
/// so every passenger falls back to the stand-in.
Future<rive.File?> loadPassengerRive({AssetBundle? bundle}) async {
  final rive.File? file;
  try {
    file = await rive.File.asset(
      passengerRiveAsset,
      riveFactory: rive.Factory.flutter,
      bundle: bundle,
    );
    // Whatever stops the character (no asset in the build, no native
    // library, a bad file), the trip plays with the stand-in.
  } on Object catch (error) {
    debugPrint('passenger.riv: $error');
    return null;
  }
  if (file == null) return null;
  final artboard = file.artboard(riveArtboardName);
  final machine = artboard?.stateMachine(riveStateMachineName);
  final model = file.viewModelByName(riveViewModelName);
  final usable = machine != null && model != null;
  machine?.dispose();
  artboard?.dispose();
  model?.dispose();
  if (usable) return file;
  debugPrint('passenger.riv: no $riveArtboardName artboard, machine or model');
  file.dispose();
  return null;
}

/// What the character shows besides its look.
@immutable
final class CharacterState {
  const CharacterState({
    required this.mood,
    required this.talking,
    required this.asleep,
    required this.headphones,
  });

  factory CharacterState.of(PassengerView view) => CharacterState(
    mood: view.mood,
    talking: view.talking,
    asleep: view.asleep,
    headphones: view.headphones,
  );

  final int mood;
  final bool talking;
  final bool asleep;

  /// On the ears; off (around the neck) while attentive.
  final bool headphones;

  @override
  bool operator ==(Object other) =>
      other is CharacterState &&
      other.mood == mood &&
      other.talking == talking &&
      other.asleep == asleep &&
      other.headphones == headphones;

  @override
  int get hashCode => Object.hash(mood, talking, asleep, headphones);

  @override
  String toString() =>
      'CharacterState(mood: $mood, talking: $talking, asleep: $asleep, '
      'headphones: $headphones)';
}

/// The view model's properties the app sets.
abstract interface class PassengerInputs {
  void setLook({required Color shirt, required String accessory});
  void setState(CharacterState state);

  /// Fires `alight`.
  void alight();
  void dispose();
}

/// What draws and animates the character.
abstract interface class CharacterRig {
  void advance(double dt);
  void render(Canvas canvas, Rect box);
  void dispose();
}

final class RivePassengerArtFactory implements PassengerArtFactory {
  const RivePassengerArtFactory(this.file);

  final rive.File file;

  @override
  PassengerArt create(SkinLook look, WassalTokens tokens) {
    final artboard = file.artboard(riveArtboardName)!;
    final machine = artboard.stateMachine(riveStateMachineName)!;
    final model = file.viewModelByName(riveViewModelName)!;
    final instance = model.createDefaultInstance() ?? model.createInstance()!;
    model.dispose();
    machine.bindViewModelInstance(instance);
    return RivePassengerArt(
      rig: _ArtboardRig(artboard, machine),
      inputs: _ViewModelInputs(instance),
      look: look,
      tokens: tokens,
    );
  }
}

/// A passenger drawn by the character.
final class RivePassengerArt implements PassengerArt {
  RivePassengerArt({
    required this._rig,
    required this._inputs,
    required SkinLook look,
    required WassalTokens tokens,
  }) {
    _inputs.setLook(
      shirt: shirtColor(tokens, look.shirt),
      accessory: look.accessory.name,
    );
  }

  final CharacterRig _rig;
  final PassengerInputs _inputs;
  CharacterState? _state;
  bool _alighted = false;

  @override
  void update(PassengerView view) {
    final state = CharacterState.of(view);
    if (state != _state) {
      _state = state;
      _inputs.setState(state);
    }
    if (view.presence == PresenceView.leaving && !_alighted) {
      _alighted = true;
      _inputs.alight();
    }
  }

  @override
  void advance(double dt) => _rig.advance(dt);

  @override
  void render(Canvas canvas, Rect box) => _rig.render(canvas, box);

  @override
  void dispose() {
    _rig.dispose();
    _inputs.dispose();
  }
}

final class _ArtboardRig implements CharacterRig {
  _ArtboardRig(this._artboard, this._machine);

  final rive.Artboard _artboard;
  final rive.StateMachine _machine;

  @override
  void advance(double dt) => _machine.advanceAndApply(dt);

  /// As flame_rive's `RiveComponent` draws, fitted into [box].
  @override
  void render(Canvas canvas, Rect box) {
    canvas.save();
    final renderer = rive.Renderer.make(canvas);
    try {
      renderer.align(
        rive.Fit.contain,
        Alignment.center,
        rive.AABB.fromValues(box.left, box.top, box.right, box.bottom),
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
    _machine.dispose();
    _artboard.dispose();
  }
}

final class _ViewModelInputs implements PassengerInputs {
  _ViewModelInputs(this._instance);

  final rive.ViewModelInstance _instance;

  @override
  void setLook({required Color shirt, required String accessory}) {
    _instance.color('shirt')?.value = shirt;
    _instance.enumerator('accessory')?.value = accessory;
  }

  @override
  void setState(CharacterState state) {
    _instance.number('mood')?.value = state.mood.toDouble();
    _instance.boolean('talking')?.value = state.talking;
    _instance.boolean('asleep')?.value = state.asleep;
    _instance.boolean('headphones')?.value = state.headphones;
  }

  @override
  void alight() => _instance.trigger('alight')?.trigger();

  @override
  void dispose() => _instance.dispose();
}
