// A story rider's comments (specs/015-m10-apartment-story, contracts/
// story-trip.md "Comments", T119): the mapped causes, the unmapped ones, the
// first rider with a pool, the same line for the same `(seed, ordinal)`, a
// zero state, and a generator that is never the engine's.
import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/features/trip/domain/rider_comments.dart';
import 'package:wassal/features/trip/domain/speech.dart';

/// A pool of [count] lines named «key 0», «key 1», …
SpeechPool _pool(String key, [int count = 5]) => SpeechPool(
  speechKey: key,
  lines: [
    for (var i = 0; i < count; i++)
      SpeechLine(text: LocalizedText(arEg: '$key $i')),
  ],
);

/// The pools every test's content has.
final _pools = {
  for (final key in [
    'short_change',
    'false_accusation',
    'fight',
    'missed_stop',
    'impatient',
    'moallem_a',
    'salma_a',
  ])
    key: _pool(key),
};

final _speech = SpeechResolver(
  pool: (key) => _pools[key],
  piasters: (_) => '',
  station: (_) => '',
);

StoryTripInfo _info(List<StoryRider> riders) => StoryTripInfo(
  title: const LocalizedText(arEg: 't'),
  riders: riders,
);

const _all = RiderComments(
  shortChange: 'short_change',
  falseAccusation: 'false_accusation',
  fight: 'fight',
  missedStop: 'missed_stop',
  impatient: 'impatient',
);

StoryRider _moallem([RiderComments? comments = _all]) => StoryRider(
  character: StoryCharacter.moallem,
  seat: 'A_l',
  comments: comments,
);

ReputationChanged _event(RepCause cause) =>
    ReputationChanged(1000, delta: -1, cause: cause, value: 2);

/// The line a pool gives for [seed] and [ordinal], computed without the
/// function under test.
String _expected(String key, int seed, int ordinal) {
  var state = (seed ^ (ordinal + 1)) & 0xFFFFFFFF;
  if (state == 0) state = 1;
  final (pick, _) = Xorshift32(state).next();
  return '$key ${pick % 5}';
}

void main() {
  const mapped = {
    RepCause.shortChange: 'short_change',
    RepCause.falseAccusation: 'false_accusation',
    RepCause.fight: 'fight',
    RepCause.missedStop: 'missed_stop',
    RepCause.impatient: 'impatient',
  };

  test('each mapped cause draws from its own pool', () {
    for (final MapEntry(:key, :value) in mapped.entries) {
      final comment = riderComment(
        _info([_moallem()]),
        _speech,
        _event(key),
        seed: 77,
        ordinal: 0,
      );
      expect(comment, isNotNull, reason: '$key');
      expect(comment!.speaker, StoryCharacter.moallem);
      expect(comment.line, _expected(value, 77, 0), reason: '$key');
      expect(comment.ordinal, 0);
    }
  });

  test('every other cause makes no comment', () {
    for (final cause in RepCause.values.where((c) => !mapped.containsKey(c))) {
      expect(
        riderComment(
          _info([_moallem()]),
          _speech,
          _event(cause),
          seed: 77,
          ordinal: 0,
        ),
        isNull,
        reason: '$cause',
      );
    }
  });

  test('a rider with no pool for the cause stays silent', () {
    final info = _info([_moallem(const RiderComments(fight: 'fight'))]);
    expect(
      riderComment(
        info,
        _speech,
        _event(RepCause.shortChange),
        seed: 1,
        ordinal: 0,
      ),
      isNull,
    );
    expect(
      riderComment(
        _info([_moallem(null)]),
        _speech,
        _event(RepCause.fight),
        seed: 1,
        ordinal: 0,
      ),
      isNull,
    );
    expect(
      riderComment(
        _info(const []),
        _speech,
        _event(RepCause.fight),
        seed: 1,
        ordinal: 0,
      ),
      isNull,
    );
  });

  test('a pool the content lacks makes no comment', () {
    final info = _info([_moallem(const RiderComments(shortChange: 'nowhere'))]);
    expect(
      riderComment(
        info,
        _speech,
        _event(RepCause.shortChange),
        seed: 1,
        ordinal: 0,
      ),
      isNull,
    );
  });

  test('two riders: the first with a pool speaks', () {
    final info = _info([
      const StoryRider(
        character: StoryCharacter.salma,
        seat: 'B_r',
        comments: RiderComments(fight: 'salma_a'),
      ),
      _moallem(const RiderComments(shortChange: 'moallem_a')),
    ]);
    // سلمى first, but she has no short-change pool: المعلم speaks.
    final short = riderComment(
      info,
      _speech,
      _event(RepCause.shortChange),
      seed: 5,
      ordinal: 2,
    );
    expect(short!.speaker, StoryCharacter.moallem);
    expect(short.line, _expected('moallem_a', 5, 2));
    // Both could answer a fight only if both named it; she is first.
    final fight = riderComment(
      info,
      _speech,
      _event(RepCause.fight),
      seed: 5,
      ordinal: 3,
    );
    expect(fight!.speaker, StoryCharacter.salma);
  });

  test('the same (seed, ordinal) is the same line; the ordinal moves it', () {
    String line(int seed, int ordinal) => riderComment(
      _info([_moallem()]),
      _speech,
      _event(RepCause.fight),
      seed: seed,
      ordinal: ordinal,
    )!.line;

    expect(line(4242, 3), line(4242, 3));
    expect({for (var i = 0; i < 40; i++) line(4242, i)}.length, greaterThan(1));
    expect(
      {for (var s = 1; s < 40; s++) line(s * 7919, 0)}.length,
      greaterThan(1),
    );
  });

  test('a zero state is state 1', () {
    // seed 1, ordinal 0: 1 ^ 1 = 0.
    final comment = riderComment(
      _info([_moallem()]),
      _speech,
      _event(RepCause.fight),
      seed: 1,
      ordinal: 0,
    );
    expect(comment!.line, _expected('fight', 1, 0));
    expect(const Xorshift32(1).next().$1, isNot(0));
  });

  test('a fresh generator per comment: the pick is Xorshift32(seed ^ '
      '(ordinal + 1)), never a state the engine holds', () {
    for (final (seed, ordinal) in [
      (123456789, 0),
      (123456789, 1),
      (0xFFFFFFFF, 9),
    ]) {
      final comment = riderComment(
        _info([_moallem()]),
        _speech,
        _event(RepCause.impatient),
        seed: seed,
        ordinal: ordinal,
      );
      expect(comment!.line, _expected('impatient', seed, ordinal));
    }
  });
}
