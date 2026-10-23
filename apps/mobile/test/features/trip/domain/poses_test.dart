import 'package:flutter_test/flutter_test.dart';
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/features/trip/domain/looks.dart';
import 'package:wassal/features/trip/domain/poses.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';

// One pose per passenger, first match wins (tasks.md T096,
// contracts/rive-characters.md "From a pose to the inputs", research R16).

PassengerView _view({
  AlightOutcome? outcome,
  bool claimOpen = false,
  bool nearStopPulse = false,
  bool asleep = false,
  bool waking = false,
  bool headphones = false,
  int mood = 0,
  bool talking = false,
}) => PassengerView(
  passengerId: 'p1',
  seatId: 'A_r',
  presence: outcome == null ? PresenceView.aboard : PresenceView.leaving,
  look: looks['regular']!,
  slot: 0,
  mood: mood,
  talking: talking,
  asleep: asleep,
  waking: waking,
  headphones: headphones,
  attentive: false,
  nearStopPulse: nearStopPulse,
  dropMeHere: false,
  ledgerBadge: null,
  outcome: outcome,
  claimOpen: claimOpen,
);

void main() {
  group('each row picks its pose', () {
    for (final (name, view, pose) in [
      (
        'a fight getting off',
        _view(outcome: AlightOutcome.fight),
        CharacterPose.fight,
      ),
      ('an open claim', _view(claimOpen: true), CharacterPose.claim),
      (
        'owed at the next stop',
        _view(nearStopPulse: true),
        CharacterPose.changeDue,
      ),
      ('asleep', _view(asleep: true), CharacterPose.sleep),
      ('waking', _view(waking: true), CharacterPose.sleep),
      ('headphones on', _view(headphones: true), CharacterPose.headphones),
      ('mood 2', _view(mood: 2), CharacterPose.impatient2),
      ('mood 3', _view(mood: 3), CharacterPose.impatient2),
      ('mood 1', _view(mood: 1), CharacterPose.impatient1),
      ('talking', _view(talking: true), CharacterPose.talk),
      ('nothing else', _view(), CharacterPose.idle),
    ]) {
      test(name, () => expect(poseFor(view, failed: false), pose));
    }
  });

  group('the first match wins', () {
    test('asleep and talking: sleep', () {
      expect(
        poseFor(_view(asleep: true, talking: true), failed: false),
        CharacterPose.sleep,
      );
    });

    test('an open claim at mood 2: claim', () {
      expect(
        poseFor(_view(claimOpen: true, mood: 2), failed: false),
        CharacterPose.claim,
      );
    });

    test('a fight beats everything', () {
      expect(
        poseFor(
          _view(
            outcome: AlightOutcome.fight,
            claimOpen: true,
            asleep: true,
            mood: 3,
            talking: true,
          ),
          failed: true,
        ),
        CharacterPose.fight,
      );
    });

    test('owed beats asleep and headphones', () {
      expect(
        poseFor(
          _view(nearStopPulse: true, asleep: true, headphones: true),
          failed: false,
        ),
        CharacterPose.changeDue,
      );
    });

    test('headphones beat a frown and talking', () {
      expect(
        poseFor(_view(headphones: true, mood: 2, talking: true), failed: false),
        CharacterPose.headphones,
      );
    });
  });

  group('a failed trip', () {
    test('frowns: impatient_2', () {
      expect(poseFor(_view(), failed: true), CharacterPose.impatient2);
      expect(
        poseFor(_view(talking: true, mood: 1), failed: true),
        CharacterPose.impatient2,
      );
    });

    test('keeps the rows above the frown', () {
      expect(poseFor(_view(asleep: true), failed: true), CharacterPose.sleep);
    });
  });
}
