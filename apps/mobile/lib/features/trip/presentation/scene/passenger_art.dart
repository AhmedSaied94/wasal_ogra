// How a passenger is drawn (research R17): the owner's Rive character, and
// wherever it doesn't draw, and in every golden, the look's static art. Both
// sit behind this interface, so the art changes without touching behavior.
import 'dart:ui';

import 'package:content_models/content_models.dart';
import 'package:wassal/features/trip/domain/looks.dart';
import 'package:wassal/features/trip/domain/poses.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';

/// Makes the art of each passenger.
abstract interface class PassengerArtFactory {
  /// The art of a passenger with [look] seated in [row]. Under
  /// [reduceMotion] it is the static art, which holds its effects still.
  PassengerArt create(
    Look look, {
    SeatRow row = SeatRow.a,
    bool reduceMotion = false,
  });
}

/// One passenger's drawing.
abstract interface class PassengerArt {
  /// The passenger's state changed.
  void update(PassengerView view);

  /// Plays a one-shot animation (contracts/rive-characters.md "Triggers").
  void play(CharacterTrigger trigger);

  /// A story rider's `surprised` face, on while its comment shows
  /// (contracts/rive-characters.md "Inputs": passengers never get it). The
  /// static art has one face.
  void surprise({required bool on});

  /// Its own animation moved on by [dt] seconds.
  void advance(double dt);

  /// Under reduced motion the art holds still: no bob, shake or float.
  abstract bool reduceMotion;

  /// Draws head and shoulders with the head filling [box], the seat's head
  /// square.
  void render(Canvas canvas, Rect box);

  void dispose();
}
