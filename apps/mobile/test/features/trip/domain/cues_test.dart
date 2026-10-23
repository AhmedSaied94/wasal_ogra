import 'package:flutter_test/flutter_test.dart';
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/core/l10n/number_formatter.dart';
import 'package:wassal/features/trip/domain/cues.dart';
import 'package:wassal/features/trip/domain/speech.dart';
import 'package:wassal/features/trip/domain/trip_facts.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';

import '../../../helpers/economy.dart';
import '../../../helpers/trip.dart';

late TripFacts facts;
late TripEngine engine;

final speech = SpeechResolver(
  pool: sampleContent().speechPool,
  piasters: const NumberFormatter(DigitStyle.western).piasters,
  station: (id) => id,
);

List<TripCue> cuesOf(List<DomainEvent> events, {TripState? before}) => mapCues(
  events,
  before: before ?? engine.state,
  after: engine.state,
  facts: facts,
  speech: speech,
);

Iterable<CueSound> sounds(List<TripCue> cues) =>
    cues.whereType<SoundCue>().map((c) => c.sound);

Iterable<HapticKind> haptics(List<TripCue> cues) =>
    cues.whereType<HapticCue>().map((c) => c.kind);

/// Channels other than sound: vibration, the scene, words.
int otherChannels(List<TripCue> cues) =>
    cues.where((c) => c is! SoundCue).length;

/// Replays [name] until a moment emits an event of type [E]: that event,
/// and its own cues.
(E, List<TripCue>) cuesAt<E extends DomainEvent>(String name) {
  final fixture = loadFixture(name);
  facts = factsFor(fixture.definition, params: fixture.params, withLine: false);
  engine = TripEngine.start(
    fixture.definition,
    fixture.params,
    seed: fixture.seed,
  );
  var next = 0;
  while (engine.status == TripStatus.running) {
    final before = engine.state;
    final List<DomainEvent> events;
    if (next < fixture.commandLog.length &&
        fixture.commandLog[next].tMs == engine.state.tMs) {
      final outcome = engine.apply(fixture.commandLog[next++].command);
      events = outcome is Accepted ? outcome.events : const [];
    } else {
      events = engine.step();
    }
    if (events.whereType<E>().firstOrNull case final event?) {
      return (event, cuesOf([event], before: before));
    }
  }
  throw StateError('$name never emits $E');
}

void main() {
  setUp(() {
    final definition = sampleTrip('line_hay.01');
    facts = factsFor(definition);
    engine = TripEngine.start(definition, facts.params)..stepTo(33);
  });

  test('a fare arriving: coin, a light tap, and a log line', () {
    // A real fare in flight, from p1.
    final fixture = loadFixture('command__pick_return_send');
    facts = factsFor(fixture.definition, params: fixture.params);
    engine = TripEngine.start(
      fixture.definition,
      fixture.params,
      seed: fixture.seed,
    );
    while (!engine.state.tokens.any((t) => t.kind == TokenKind.fare)) {
      engine.step();
    }
    final token = engine.state.tokens.firstWhere(
      (t) => t.kind == TokenKind.fare,
    );
    final cues = cuesOf([
      MoneyArrivedAtDriver(
        engine.state.tMs,
        tokenId: token.tokenId,
        kind: TokenKind.fare,
        amountPiasters: token.pieces.total,
      ),
    ]);
    expect(sounds(cues), [CueSound.coin]);
    expect(haptics(cues), [HapticKind.light]);
    final log = cues.whereType<LogCue>().single.line;
    expect(log.kind, LogKind.fareArrived);
    expect(log.amountPiasters, token.pieces.total);
    expect(log.speaker, isNotNull);
  });

  test(
    'change delivered: exact thanks, short wrong, over and not owed silent',
    () {
      ChangeDelivered delivered(ChangeResult result) => ChangeDelivered(
        33,
        tokenId: 1,
        passengerId: 'p1',
        result: result,
        amountPiasters: 300,
      );
      expect(sounds(cuesOf([delivered(ChangeResult.exact)])), [
        CueSound.thanks,
      ]);
      final short = cuesOf([delivered(ChangeResult.short)]);
      expect(sounds(short), [CueSound.wrong]);
      expect(short.whereType<FlashCue>().single.passengerId, 'p1');
      expect(cuesOf([delivered(ChangeResult.over)]), isEmpty);
      expect(cuesOf([delivered(ChangeResult.notOwed)]), isEmpty);
    },
  );

  test('stations: a warning calls, a stop honks', () {
    expect(
      sounds(
        cuesOf([
          const StationWarning(
            33,
            stationId: 'madrasa',
            atMs: 30000,
            alighting: ['p1'],
            owed: ['p1'],
          ),
        ]),
      ),
      [CueSound.call],
    );
    expect(sounds(cuesOf([const StationReached(33, stationId: 'madrasa')])), [
      CueSound.horn,
    ]);
  });

  test('a fight shakes and vibrates; a missed stop is wrong', () {
    final fight = cuesOf([
      const PassengerAlighted(
        33,
        passengerId: 'p1',
        outcome: AlightOutcome.fight,
      ),
    ]);
    expect(sounds(fight), [CueSound.fight]);
    expect(haptics(fight), [HapticKind.heavy]);
    expect(fight.whereType<ShakeCue>(), hasLength(1));
    expect(otherChannels(fight), greaterThanOrEqualTo(2));
    expect(
      sounds(
        cuesOf([
          const PassengerAlighted(
            33,
            passengerId: 'p1',
            outcome: AlightOutcome.missedStop,
          ),
        ]),
      ),
      [CueSound.wrong],
    );
    expect(
      cuesOf([
        const PassengerAlighted(
          33,
          passengerId: 'p1',
          outcome: AlightOutcome.thanked,
        ),
      ]),
      isEmpty,
    );
  });

  test('a blocked token makes no sound', () {
    expect(cuesOf([const TokenBlocked(33, tokenId: 1, by: 'p2')]), isEmpty);
  });

  test('a throw highlights the passenger', () {
    final cues = cuesOf([
      const ChangeSent(33, passengerId: 'p1', tokenId: 1, amountPiasters: 300),
    ]);
    expect(cues.whereType<HighlightCue>().single.passengerId, 'p1');
  });

  test('a passenger line becomes a line cue with its speaker and style', () {
    final cues = cuesOf([
      PassengerSpeaks(
        33,
        passengerId: 'p1',
        slot: SpeechSlot.wantsChange,
        speechKey: SpeechSlot.wantsChange.defaultKey,
        variant: 0,
        amountPiasters: 300,
      ),
    ]);
    final line = cues.whereType<LineCue>().single;
    expect(line.passengerId, 'p1');
    expect(line.style, BubbleStyle.warning);
    expect(line.text, contains('3'));
    expect(line.speaker.labelKey, 'tripLookEffendi');
  });

  test('the spoken rejections are exactly the four', () {
    expect(
      [
        for (final code in RejectionCode.values)
          if (rejectionSpoken(code)) code,
      ],
      unorderedEquals([
        RejectionCode.cannotMakeChange,
        RejectionCode.breakLimit,
        RejectionCode.boosterLimit,
        RejectionCode.commandLimit,
      ]),
    );
  });
  group('the events (US4)', () {
    test('notes dropped: bump, a heavy tap, a shake and a log line', () {
      final (event, cues) = cuesAt<MoneyDropped>(
        'event__bump_collect_and_lose',
      );
      expect(sounds(cues), [CueSound.bump]);
      expect(haptics(cues), [HapticKind.heavy]);
      expect(cues.whereType<ShakeCue>(), hasLength(1));
      final log = cues.whereType<LogCue>().single.line;
      expect(log.kind, LogKind.dropped);
      final token = engine.state.tokens.firstWhere(
        (t) => t.tokenId == event.tokenId,
      );
      expect(log.amountPiasters, token.pieces.total);
    });

    test('notes lost: a log line, no sound', () {
      final (_, cues) = cuesAt<DroppedLost>('event__bump_collect_and_lose');
      expect(sounds(cues), isEmpty);
      expect(cues.whereType<LogCue>().single.line.kind, LogKind.lost);
    });

    test('the fare goes up: alert, the banner and a log line', () {
      final (event, cues) = cuesAt<FareIncreased>('event__fare_increase');
      expect(sounds(cues), [CueSound.alert]);
      final banner = cues.whereType<BannerCue>().single;
      expect(banner.newPiasters - banner.oldPiasters, event.amountPiasters);
      expect(banner.oldPiasters, greaterThan(0));
      final log = cues.whereType<LogCue>().single.line;
      expect(log.kind, LogKind.fareUp);
      expect(log.amountPiasters, event.amountPiasters);
    });

    test('a note broken: coin, a light tap and a log line', () {
      final (event, cues) = cuesAt<BreakCompleted>('command__request_break');
      expect(sounds(cues), [CueSound.coin]);
      expect(haptics(cues), [HapticKind.light]);
      final log = cues.whereType<LogCue>().single.line;
      expect(log.kind, LogKind.breakDone);
      expect(log.amountPiasters, event.denomination);
    });
  });
}
