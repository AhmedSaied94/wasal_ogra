// What a character shows (008.5 contracts/rive-characters.md "From a pose
// to the inputs", research R16): one looping pose per passenger, picked from
// its view, first match wins; and the one-shots the file plays on a cue.
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';

/// A character's loop. `surprised` and `angry` are the story characters'.
enum CharacterPose {
  idle,
  talk,
  impatient1,
  impatient2,
  sleep,
  headphones,
  changeDue,
  fight,
  claim,
  surprised,
  angry,
}

/// The file's one-shots. Waking and taking the headphones off play from the
/// view's `asleep` and `headphones` turning false; getting off, from its
/// `leaving`.
enum CharacterTrigger { board, alight, call, happy, targeted }

/// [view]'s pose; [failed] when the trip failed, which frowns like a low
/// mood.
CharacterPose poseFor(PassengerView view, {required bool failed}) {
  if (view.outcome == AlightOutcome.fight) return CharacterPose.fight;
  if (view.claimOpen) return CharacterPose.claim;
  if (view.nearStopPulse) return CharacterPose.changeDue;
  if (view.asleep || view.waking) return CharacterPose.sleep;
  if (view.headphones) return CharacterPose.headphones;
  if (failed || view.mood >= 2) return CharacterPose.impatient2;
  if (view.mood == 1) return CharacterPose.impatient1;
  if (view.talking) return CharacterPose.talk;
  return CharacterPose.idle;
}
