import 'dart:io';

import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/features/trip/domain/presentation_memory.dart';
import 'package:wassal/features/trip/domain/projection.dart';
import 'package:wassal/features/trip/domain/rider_comments.dart';
import 'package:wassal/features/trip/domain/looks.dart';
import 'package:wassal/features/trip/domain/trip_facts.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';
import 'package:wassal/features/trip/domain/view_value.dart';

import '../../../helpers/trip.dart';

/// Plays [fixture]'s log on [engine] until [stop] holds or the log ends.
/// Returns every event, in order.
List<DomainEvent> playUntil(
  TripEngine engine,
  ParityFixture fixture,
  bool Function(TripState state) stop,
) {
  final events = <DomainEvent>[];
  var next = 0;
  while (!stop(engine.state) && engine.status == TripStatus.running) {
    while (next < fixture.commandLog.length &&
        fixture.commandLog[next].tMs == engine.state.tMs) {
      final outcome = engine.apply(fixture.commandLog[next++].command);
      if (outcome is Accepted) events.addAll(outcome.events);
      if (stop(engine.state)) return events;
    }
    events.addAll(engine.step());
  }
  return events;
}

TripEngine engineFor(ParityFixture fixture) =>
    TripEngine.start(fixture.definition, fixture.params, seed: fixture.seed);

/// The field names of data-model.md's "The view" table, by type.
Map<String, List<String>> documentedFields() {
  final text = File('../../specs/008-m02-trip-screen/data-model.md')
      .readAsStringSync();
  final start = text.indexOf('| Type | Fields |');
  final rows = text.substring(start).split('\n').skip(2);
  final result = <String, List<String>>{};
  for (final row in rows) {
    if (!row.startsWith('| `')) break;
    final cells = row.split(' | ');
    final type = RegExp('`([A-Za-z]+)`').firstMatch(cells[0])![1]!;
    final names = <String>[];
    var depth = 0;
    var item = StringBuffer();
    for (final char in cells[1].split('')) {
      if (char == '(') depth++;
      if (char == ')') depth--;
      if (char == ',' && depth == 0) {
        names.add(item.toString());
        item = StringBuffer();
      } else {
        item.write(char);
      }
    }
    names.add(item.toString());
    result[type] = [
      for (final name in names) RegExp('`([A-Za-z]+)').firstMatch(name)![1]!,
    ];
  }
  return result;
}

void main() {
  group('top bar', () {
    test('trip number, line name, reputation', () {
      final definition = sampleTrip('line_gamaa.02');
      final facts = factsFor(definition);
      final view = viewOf(TripEngine.start(definition, facts.params), facts);
      expect(view.topBar.tripNumber, 2);
      expect(view.topBar.lineName, sampleLine('line_gamaa').name.arEg);
      expect(view.topBar.reputation, 100);
      expect(view.topBar.reputationLow, isFalse);
    });

    test('no line, no name', () {
      final definition = sampleTrip('line_hay.01');
      final facts = factsFor(definition, withLine: false);
      final view = viewOf(TripEngine.start(definition, facts.params), facts);
      expect(view.topBar.lineName, isNull);
      expect(view.topBar.tripNumber, 1);
    });

    test('reputation below 40 is low', () {
      final fixture = loadFixture('ending__failed');
      final engine = engineFor(fixture);
      final facts = factsFor(fixture.definition, params: fixture.params);
      playUntil(engine, fixture, (s) => s.reputation < reputationLowBelow);
      expect(viewOf(engine, facts).topBar.reputationLow, isTrue);
    });
  });

  group('money', () {
    test('a fare in flight is a fare token, change is a change token', () {
      final fixture = loadFixture('command__pick_return_send');
      final engine = engineFor(fixture);
      final facts = factsFor(fixture.definition, params: fixture.params);
      playUntil(engine, fixture, (s) => s.tokens.any((t) => t.hop != null));
      var view = viewOf(engine, facts);
      final fare = view.tokens.firstWhere((t) => t.kind == TokenTint.fare);
      expect(fare.atHolder, isFalse);
      expect(fare.hopMs, greaterThan(0));
      expect(fare.blocked, isFalse);
      expect(fare.dropped, isFalse);
      engine.step();
      final later = viewOf(
        engine,
        facts,
      ).tokens.firstWhere((t) => t.tokenId == fare.tokenId);
      expect(later.progressPermille, greaterThan(fare.progressPermille));

      playUntil(
        engine,
        fixture,
        (s) => s.tokens.any((t) => t.kind == TokenKind.change),
      );
      view = viewOf(engine, facts);
      expect(view.tokens.any((t) => t.kind == TokenTint.change), isTrue);
    });

    test('a token a sleeper holds up is blocked', () {
      final fixture = loadFixture('archetype__sleeper_blocks_chain');
      final engine = engineFor(fixture);
      final facts = factsFor(fixture.definition, params: fixture.params);
      playUntil(
        engine,
        fixture,
        (s) => s.tokens.any((t) => t.blockedBy != null),
      );
      expect(viewOf(engine, facts).tokens.any((t) => t.blocked), isTrue);
    });

    test('money on the floor is dropped, with its deadline', () {
      final fixture = loadFixture('event__bump_collect_and_lose');
      final engine = engineFor(fixture);
      final facts = factsFor(fixture.definition, params: fixture.params);
      playUntil(engine, fixture, (s) => s.tokens.any((t) => t.isDropped));
      final view = viewOf(engine, facts);
      final token = view.tokens.firstWhere((t) => t.dropped);
      final dropped = view.dropped.firstWhere(
        (d) => d.tokenId == token.tokenId,
      );
      expect(dropped.tokenId, token.tokenId);
      expect(dropped.untilMs, greaterThan(view.tMs));
      expect(dropped.amountPiasters, token.amountPiasters);
    });

    test('hand, tray, break button and undo come from the engine', () {
      final fixture = loadFixture('command__undo_last_send');
      final engine = engineFor(fixture);
      final facts = factsFor(fixture.definition, params: fixture.params);
      var view = viewOf(engine, facts);
      expect(view.tray.map((s) => s.denomination), trayDenominations);
      for (final slot in view.tray) {
        expect(slot.count, engine.state.tray.count(slot.denomination));
        expect(slot.breakable, isFalse);
      }
      expect(view.hand.isEmpty, isTrue);
      expect(view.breakButton.left, engine.state.breaksLeft);
      expect(view.breakButton.enabled, isTrue);
      expect(view.undoUntilMs, isNull);

      engine.apply(const PickFromTray(100));
      view = viewOf(engine, facts);
      expect(view.hand.pieces, {100: 1});
      expect(view.hand.totalPiasters, 100);

      playUntil(engine, fixture, (s) => s.undoAvailableUntilMs != null);
      view = viewOf(engine, facts);
      expect(view.undoUntilMs, engine.state.undoAvailableUntilMs);

      final breakMode = viewOf(
        engine,
        facts,
        screen: const TripScreenState(
          phase: TripPhase.running,
          breakMode: true,
        ),
      );
      for (final slot in breakMode.tray) {
        expect(
          slot.breakable,
          slot.count > 0 &&
              slot.denomination >= facts.params.tripBreakMinPiasters,
        );
      }

      final paused = viewOf(
        engine,
        facts,
        screen: const TripScreenState(phase: TripPhase.paused),
      );
      expect(paused.breakButton.enabled, isFalse);
    });
  });

  group('passengers', () {
    test('boarding, then aboard, then leaving, then gone', () {
      final definition = sampleTrip('line_hay.01');
      final facts = factsFor(definition);
      final engine = TripEngine.start(definition, facts.params);
      var memory = PresentationMemory.empty;
      void step() => memory = memory.update(
        engine.step(),
        const [],
        tMs: engine.state.tMs,
        bubbleMinMs: 4000,
      );

      // Passengers aboard at the start walk in on the first step.
      final boarded = engine.step();
      memory = memory.update(
        boarded,
        const [],
        tMs: engine.state.tMs,
        bubbleMinMs: 4000,
      );
      var view = viewOf(engine, facts, memory: memory);
      if (boarded.any((e) => e is PassengerBoarded)) {
        expect(view.passenger('p1')!.presence, PresenceView.boarding);
        while (engine.state.tMs < walkMs + 33) {
          step();
        }
      }
      view = viewOf(engine, facts, memory: memory);
      expect(view.passenger('p1')!.presence, PresenceView.aboard);
      expect(view.passenger('p1')!.look, looks[skinAliases['effendi_suit']]);
      expect(view.passenger('p1')!.slot, 0);
      expect(view.passenger('p2')!.slot, 1);

      while (engine.state.passenger('p1')!.presence == Presence.aboard) {
        step();
      }
      view = viewOf(engine, facts, memory: memory);
      expect(view.passenger('p1')!.presence, PresenceView.leaving);
      expect(view.passenger('p1')!.outcome, isNotNull);
      final leftAt = engine.state.tMs;
      while (engine.state.tMs < leftAt + walkMs) {
        step();
      }
      view = viewOf(engine, facts, memory: memory);
      expect(view.passenger('p1'), isNull);
    });

    test('mood follows patience, and a failed trip angers everyone', () {
      final fixture = loadFixture('core__patience_runs_out');
      final engine = engineFor(fixture);
      final facts = factsFor(fixture.definition, params: fixture.params);
      playUntil(
        engine,
        fixture,
        (s) => s.passengers.any((p) => (p.patiencePermille ?? 1000) <= 333),
      );
      final view = viewOf(engine, facts);
      expect(view.passengers.map((p) => p.mood), contains(2));

      final failed = loadFixture('ending__failed');
      final failing = engineFor(failed);
      playUntil(failing, failed, (s) => s.status == TripStatus.failed);
      final failedView = viewOf(
        failing,
        factsFor(failed.definition, params: failed.params),
      );
      expect(failedView.passengers.every((p) => p.mood == 3), isTrue);
      expect(failedView.failSummary, isNotNull);
      expect(failedView.failSummary!.causes, isNotEmpty);
    });

    test('the ledger badge shows only during a peek', () {
      final fixture = loadFixture('booster__ledger_peek');
      final engine = engineFor(fixture);
      final facts = factsFor(fixture.definition, params: fixture.params);
      expect(
        viewOf(engine, facts).passengers.every((p) => p.ledgerBadge == null),
        isTrue,
      );
      playUntil(engine, fixture, (s) => s.ledgerPeekActive);
      final view = viewOf(engine, facts);
      expect(view.passengers.every((p) => p.ledgerBadge != null), isTrue);
    });
  });

  test('a story trip shows its no-fights condition', () {
    final definition = sampleTrip('line_hay.03');
    final facts = factsFor(definition);
    final view = viewOf(TripEngine.start(definition, facts.params), facts);
    expect(
      view.storyCondition,
      definition.rules.noFightsRequired ? isTrue : isNull,
    );
    final regular = sampleTrip('line_hay.01');
    expect(
      viewOf(
        TripEngine.start(regular, facts.params),
        factsFor(regular),
      ).storyCondition,
      isNull,
    );
  });

  group('a story trip\'s presentation (specs/015-m10-apartment-story)', () {
    const info = StoryTripInfo(
      title: LocalizedText(arEg: 'مشوار المعلم'),
      condition: LocalizedText(arEg: 'من غير ما حد يزعل'),
      failReason: LocalizedText(arEg: 'المعلم زعل'),
      riders: [StoryRider(character: StoryCharacter.moallem, seat: 'A_l')],
    );

    TripView viewWith(String tripId, {StoryTripInfo? storyInfo}) {
      final definition = sampleTrip(tripId);
      final facts = factsFor(definition, storyInfo: storyInfo);
      return viewOf(TripEngine.start(definition, facts.params), facts);
    }

    test('the strip: a rule alone says M02\'s line, unbroken', () {
      final view = viewWith('line_hay.03');
      expect(view.storyStrip, const StoryStripView(text: null, broken: false));
      expect(view.topBar.storyTitle, isNull);
    });

    test('the strip: the content\'s condition on top of the rule', () {
      final view = viewWith('line_hay.03', storyInfo: info);
      expect(
        view.storyStrip,
        const StoryStripView(text: 'من غير ما حد يزعل', broken: false),
      );
      expect(view.topBar.storyTitle, 'مشوار المعلم');
    });

    test('the strip: a condition without a rule never breaks', () {
      // line_hay.01 is no story trip, so it has no rule; the content's
      // condition alone still shows the strip.
      final view = viewWith('line_hay.01', storyInfo: info);
      expect(
        view.storyStrip,
        const StoryStripView(text: 'من غير ما حد يزعل', broken: null),
      );
      expect(view.storyCondition, isNull);
    });

    test('no strip without a rule or a condition', () {
      expect(viewWith('line_hay.01').storyStrip, isNull);
      const bare = StoryTripInfo(
        title: LocalizedText(arEg: 'مشوار'),
        riders: [],
      );
      final view = viewWith('line_hay.01', storyInfo: bare);
      expect(view.storyStrip, isNull);
      expect(view.topBar.storyTitle, 'مشوار');
    });

    test('a rider\'s comment shows over its seat, and only a rider\'s', () {
      final definition = sampleTrip('line_hay.03');
      final facts = factsFor(definition, storyInfo: info);
      final engine = TripEngine.start(definition, facts.params);
      final said = PresentationMemory.empty
          .update(
            const [],
            const [],
            tMs: 0,
            bubbleMinMs: 4000,
            riderComments: const [
              RiderComment(
                speaker: StoryCharacter.moallem,
                line: 'الفكة يا أسطى',
                ordinal: 0,
              ),
            ],
          )
          .characterAt(null, tMs: 0, bubbleMinMs: 4000);
      expect(
        viewOf(engine, facts, memory: said).riderBubble,
        const RiderBubbleView(
          speaker: StoryCharacter.moallem,
          seatId: 'A_l',
          text: 'الفكة يا أسطى',
        ),
      );
      // بلية's bubble is the hint's, not a rider's.
      final belya = PresentationMemory.empty.characterAt(
        (
          source: 'tripHintOwed',
          line: const HintView(key: 'tripHintOwed', targetPassengerId: 'a'),
        ),
        tMs: 0,
        bubbleMinMs: 4000,
      );
      expect(viewOf(engine, facts, memory: belya).riderBubble, isNull);
      expect(viewOf(engine, facts).riderBubble, isNull);
    });
  });

  test('boosters: stock, price when out, traffic jam limit', () {
    final definition = sampleTrip('line_hay.01');
    final facts = factsFor(definition);
    final engine = TripEngine.start(definition, facts.params);
    final view = viewOf(
      engine,
      facts,
      screen: const TripScreenState(
        phase: TripPhase.running,
        inventory: {BoosterId.changeBag: 2},
        boosterPrices: {
          BoosterId.changeBag: 10,
          BoosterId.ledgerPeek: 12,
          BoosterId.wakeAll: 8,
        },
      ),
    );
    final byId = {for (final b in view.boosters) b.booster: b};
    expect(view.boosters.map((b) => b.booster), tripBoosters);
    expect(byId[BoosterId.changeBag]!.count, 2);
    expect(byId[BoosterId.changeBag]!.priceBonat, isNull);
    expect(byId[BoosterId.changeBag]!.enabled, isTrue);
    expect(byId[BoosterId.ledgerPeek]!.priceBonat, 12);
    expect(byId[BoosterId.ledgerPeek]!.enabled, isTrue);
    expect(byId[BoosterId.trafficJam]!.enabled, isFalse);
    expect(view.boosters.every((b) => !b.adOffered), isTrue);
  });

  test('the view types are exactly data-model.md, with nothing on payment', () {
    final definition = sampleTrip('line_hay.02');
    final facts = factsFor(definition);
    final view = viewOf(TripEngine.start(definition, facts.params), facts);
    final instances = <ViewValue>[
      view,
      view.topBar,
      view.strip,
      view.strip.chips.first,
      PassengerView(
        passengerId: 'p',
        seatId: 's',
        presence: PresenceView.aboard,
        look: looks.values.first,
        slot: 0,
        mood: 0,
        talking: false,
        asleep: false,
        waking: false,
        headphones: false,
        attentive: false,
        nearStopPulse: false,
        dropMeHere: false,
        ledgerBadge: null,
        outcome: null,
      ),
      const TokenView(
        tokenId: 0,
        kind: TokenTint.fare,
        amountPiasters: 0,
        from: null,
        to: null,
        progressPermille: 0,
        hopMs: 0,
        blocked: false,
        dropped: false,
        atHolder: true,
      ),
      const DroppedMoneyView(
        tokenId: 0,
        amountPiasters: 0,
        from: null,
        to: null,
        progressPermille: 0,
        untilMs: 0,
      ),
      view.windows,
      view.hand,
      view.tray.first,
      view.breakButton,
      view.boosters.first,
      const ClaimChoice(passengerId: 'p'),
      const ChangeRequestChoice(passengerId: 'p', notePiasters: 0),
      const DisputeChoice(disputeId: 0, a: 'a', b: 'b'),
      const BubbleView(
        passengerId: 'p',
        text: '',
        style: BubbleStyle.plain,
        shownAtMs: 0,
      ),
      const SpeakerLabel(labelKey: 'k'),
      const LogLine(kind: LogKind.speech),
      const HintView(key: 'k', targetPassengerId: null),
      const BannerView(oldPiasters: 0, newPiasters: 0, shownAtMs: 0),
      const StoryStripView(),
      const RiderBubbleView(
        speaker: StoryCharacter.salma,
        seatId: 's',
        text: '',
      ),
      const FailSummary(causes: [], revive: null),
      const FailCause(cause: RepCause.fight, count: 1),
      const ReviveOffer(priceBonat: 0, affordable: false),
      const RejectionLine(code: RejectionCode.breakLimit, untilMs: 0),
    ];
    final documented = documentedFields();
    expect(
      documented.keys.toSet(),
      instances.map((i) => i.runtimeType.toString()).toSet(),
    );
    final forbidden = RegExp(
      'fare(?!Arrived|Up)|paid|payment|balance|debt|owe',
      caseSensitive: false,
    );
    for (final instance in instances) {
      final type = instance.runtimeType.toString();
      expect(instance.fields.keys.toList(), documented[type], reason: type);
      for (final field in instance.fields.keys) {
        if (type == 'StationChip' && field == 'farePiasters') continue;
        expect(field, isNot(matches(forbidden)), reason: '$type.$field');
      }
    }
  });

  test('a view equals another with the same fields', () {
    final definition = sampleTrip('line_hay.01');
    final facts = factsFor(definition);
    final a = viewOf(TripEngine.start(definition, facts.params), facts);
    final b = viewOf(TripEngine.start(definition, facts.params), facts);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });
}
