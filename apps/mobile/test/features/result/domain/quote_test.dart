// The result's quote (specs/013-m08-home-result, research R14): the trip
// replayed through the engine's public API, then the last thanks or tip,
// else the last payment from a passenger who paid in full, else none.
import 'package:flutter_test/flutter_test.dart';
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/features/result/domain/quote.dart';
import 'package:wassal/features/trip/domain/looks.dart';

import '../../../helpers/trip.dart';

/// The budget of a replay of the longest trip on CI.
const _budgetMs = 150;
const _timedRuns = 5;

ReplayRecord _recordOf(ParityFixture f) => ReplayRecord(
  definition: f.definition,
  seed: f.seed,
  params: f.params,
  commandLog: f.commandLog,
  tMs: f.expectedResult.durationMs,
);

PassengerSpeaks _says(String passenger, SpeechSlot slot, {int variant = 0}) =>
    PassengerSpeaks(
      0,
      passengerId: passenger,
      slot: slot,
      speechKey: 'key_${slot.name}_$passenger',
      variant: variant,
    );

/// Plays [log] on [engine] as the trip did: each command at its time.
void _play(TripEngine engine, Iterable<LoggedCommand> log) {
  for (final entry in log) {
    engine.stepTo(entry.tMs);
    expect(engine.apply(entry.command), isA<Accepted>());
  }
}

void main() {
  final definition = loadFixture('archetype__group_payer_redirect').definition;

  group('the rule', () {
    String? speakerOf(List<PassengerSpeaks> lines) =>
        quoteFrom(lines, definition)?.speechKey;

    test('the last thanks or tip', () {
      expect(
        speakerOf([
          _says('p1', SpeechSlot.pays),
          _says('p1', SpeechSlot.thanks),
          _says('p2', SpeechSlot.tip),
          _says('p2', SpeechSlot.pays),
        ]),
        'key_tip_p2',
      );
    });

    test('else the last payment from a passenger who paid in full', () {
      expect(
        speakerOf([
          _says('p1', SpeechSlot.paysGroup),
          _says('p2', SpeechSlot.pays),
          _says('p2', SpeechSlot.shortChange),
        ]),
        'key_paysGroup_p1',
      );
      expect(
        speakerOf([
          _says('p1', SpeechSlot.pays),
          _says('p2', SpeechSlot.paysRest),
        ]),
        'key_paysRest_p2',
      );
      for (final unhappy in [SpeechSlot.fight, SpeechSlot.accused]) {
        expect(
          speakerOf([
            _says('p1', SpeechSlot.pays),
            _says('p2', SpeechSlot.pays),
            _says('p2', unhappy),
          ]),
          'key_pays_p1',
        );
      }
    });

    test('else none', () {
      expect(
        speakerOf([
          _says('p1', SpeechSlot.pays),
          _says('p1', SpeechSlot.fight),
          _says('p2', SpeechSlot.impatient),
        ]),
        isNull,
      );
      expect(speakerOf(const []), isNull);
    });

    test("the quote is the line's, with its passenger's look and label", () {
      const line = PassengerSpeaks(
        0,
        passengerId: 'p2',
        slot: SpeechSlot.tip,
        speechKey: 'tip_generic',
        variant: 3,
        amountPiasters: 200,
      );
      final spec = definition.passengers.firstWhere(
        (p) => p.passengerId == 'p2',
      );
      expect(
        quoteFrom([line], definition),
        Quote(
          passengerId: 'p2',
          look: lookFor(spec.skin, spec.archetype),
          labelKey: lookFor(spec.skin, spec.archetype).labelKey,
          speechKey: 'tip_generic',
          variant: 3,
          amountPiasters: 200,
        ),
      );
      // A group payer speaks as «الشلة».
      final payer = quoteFrom([_says('p1', SpeechSlot.thanks)], definition)!;
      expect(payer.labelKey, groupLabelKey);
    });
  });

  test('a regular customer\'s tip is the quote of its trip', () {
    final quote = pickQuote(
      _recordOf(loadFixture('archetype__regular_customer_tip')),
    );
    expect(quote, isNotNull);
    expect(quote!.speechKey, contains('tip'));
  });

  test('the replay ends on the record\'s result, for every finished '
      'fixture', () {
    for (final name in allFixtureNames()) {
      final f = loadFixture(name);
      if (f.expectedResult.outcome != TripOutcome.finished) continue;
      final replayed = replaySpeech(_recordOf(f));
      expect(
        replayed.result?.toJson(),
        f.expectedResult.toJson(),
        reason: name,
      );
    }
  });

  test('the same quote after a kill and a rebuild', () {
    final f = loadFixture('archetype__regular_customer_tip');
    final half = f.commandLog.length ~/ 2;
    final straight = pickQuote(_recordOf(f));

    final first = TripEngine.start(f.definition, f.params, seed: f.seed);
    _play(first, f.commandLog.take(half));
    // Killed here: the lines said so far are lost with the process.
    final rebuilt = TripEngine.rebuild(first.replayRecord)..resume();
    _play(rebuilt, f.commandLog.skip(half));
    while (rebuilt.status == TripStatus.running) {
      rebuilt.step();
    }
    expect(rebuilt.result!.toJson(), f.expectedResult.toJson());
    expect(pickQuote(rebuilt.replayRecord), straight);
  });

  test('the longest trip replays within $_budgetMs ms', () {
    final record = _recordOf(loadFixture('stress__longest_trip'));
    // The best of a few runs after one warm-up, so a busy runner's noise
    // doesn't fail the budget.
    pickQuote(record);
    var best = -1;
    for (var i = 0; i < _timedRuns; i++) {
      final watch = Stopwatch()..start();
      pickQuote(record);
      final ms = watch.elapsedMilliseconds;
      if (best < 0 || ms < best) best = ms;
    }
    expect(best, lessThan(_budgetMs));
  });
}
