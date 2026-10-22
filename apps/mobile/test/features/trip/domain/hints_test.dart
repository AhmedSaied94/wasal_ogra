import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/features/trip/domain/hints.dart';
import 'package:wassal/features/trip/domain/trip_facts.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';
import 'package:wassal/features/trip/domain/wire.dart';

import '../../../helpers/trip.dart';

// بلية's hints by the line's mode (tasks.md T075, contracts/trip-view.md
// "Hints").

const _minMs = 4000;

/// One moment of a replay: the hint shown after it.
typedef Moment = ({
  int tMs,
  HintView? hint,
  TripState state,
  List<DomainEvent> events,
});

/// Every moment of [fixture]'s replay, with the hints in [mode].
List<Moment> hintsOf(
  ParityFixture fixture,
  HintMode mode, {
  Set<String> seen = const {},
}) {
  final facts = factsFor(
    fixture.definition,
    params: fixture.params,
    withLine: false,
    hintMode: mode,
    bubbleMinMs: _minMs,
  );
  final engine = TripEngine.start(
    fixture.definition,
    fixture.params,
    seed: fixture.seed,
  );
  var hints = HintState.empty.opened(
    state: engine.state,
    facts: facts,
    seen: seen,
  );
  // The opening: those aboard are seen for the first time.
  final opening = [
    for (final p in engine.state.passengers)
      if (p.presence == Presence.aboard)
        PassengerBoarded(0, passengerId: p.passengerId, seatId: p.seatId),
  ];
  final moments = <Moment>[
    (tMs: 0, hint: hints.showing, state: engine.state, events: opening),
  ];
  void fold(List<DomainEvent> events) {
    hints = hints.update(events, state: engine.state, facts: facts, seen: seen);
    moments.add((
      tMs: engine.state.tMs,
      hint: hints.showing,
      state: engine.state,
      events: events,
    ));
  }

  for (final entry in fixture.commandLog) {
    while (engine.state.tMs < entry.tMs &&
        engine.status == TripStatus.running) {
      fold(engine.step());
    }
    final outcome = engine.apply(entry.command);
    fold(outcome is Accepted ? outcome.events : const []);
  }
  while (engine.status == TripStatus.running) {
    fold(engine.step());
  }
  return moments;
}

/// The moments a new hint starts showing.
List<Moment> starts(List<Moment> moments) => [
  for (final (i, m) in moments.indexed)
    if (m.hint != null && (i == 0 || moments[i - 1].hint != m.hint)) m,
];

/// What first shows [archetype] on screen (contracts/trip-view.md "Hints").
bool triggers(Archetype archetype, DomainEvent event, String? target) =>
    switch ((archetype, event)) {
      (
        Archetype.sleeper ||
            Archetype.headphones ||
            Archetype.hurry ||
            Archetype.chatty,
        PassengerBoarded(:final passengerId),
      ) =>
        passengerId == target,
      (Archetype.hajja, TokenHopStarted(:final from, :final to)) => [
        from,
        to,
      ].any((h) => !h.isDriver && h.passengerId == target),
      (Archetype.bigNote || Archetype.student, FareSent(:final passengerId)) =>
        passengerId == target,
      (
        Archetype.groupPayer,
        PassengerSpeaks(:final passengerId, :final slot),
      ) =>
        slot == SpeechSlot.paysGroup && passengerId == target,
      (
        Archetype.regularCustomer,
        PassengerSpeaks(:final passengerId, :final slot),
      ) =>
        slot == SpeechSlot.tip && passengerId == target,
      (Archetype.falseClaimer, ClaimRaised()) => target == null,
      (Archetype.honest, ExcessReturned(:final passengerId)) =>
        passengerId == target,
      _ => false,
    };

const _firstTimeFixtures = {
  Archetype.sleeper: 'archetype__sleeper_missed_stop',
  Archetype.headphones: 'archetype__headphones_called_twice',
  Archetype.hajja: 'archetype__hajja_slow_hop',
  Archetype.hurry: 'archetype__hurry_impatient',
  Archetype.bigNote: 'archetype__big_note_drains_tray',
  Archetype.student: 'archetype__student_half_fare',
  Archetype.groupPayer: 'archetype__group_payer_redirect',
  Archetype.chatty: 'archetype__chatty_row',
  Archetype.falseClaimer: 'archetype__false_claimer_believed',
  Archetype.honest: 'archetype__honest_returns_excess',
  Archetype.regularCustomer: 'archetype__regular_customer_tip',
};

void main() {
  group('always', () {
    test('points at the first owed passenger from the warning', () {
      var shown = 0;
      var clearedEarly = 0;
      for (final name in allFixtureNames()) {
        final moments = hintsOf(loadFixture(name), HintMode.always);
        for (final (i, m) in moments.indexed) {
          final hint = m.hint;
          final before = i == 0 ? null : moments[i - 1].hint;
          if (hint != null) {
            expect(hint.key, owedHintKey);
            expect(
              m.state.passenger(hint.targetPassengerId!)!.isOwed,
              isTrue,
              reason: '$name at ${m.tMs}',
            );
          }
          if (hint != null && hint != before) {
            shown++;
            final warning = m.events.whereType<StationWarning>().last;
            expect(hint.targetPassengerId, warning.owed.first);
          }
          if (m.events.whereType<StationReached>().isNotEmpty &&
              m.events.whereType<StationWarning>().isEmpty) {
            expect(hint, isNull, reason: '$name at ${m.tMs}');
          }
          if (before != null &&
              hint == null &&
              m.events.whereType<StationReached>().isEmpty) {
            clearedEarly++;
          }
        }
      }
      expect(shown, greaterThan(0));
      // Paid back before the station.
      expect(clearedEarly, greaterThan(0));
    });
  });

  group('first time', () {
    for (final MapEntry(key: archetype, value: name)
        in _firstTimeFixtures.entries) {
      final key = firstTimeHintKey(archetype)!;

      test('${archetype.name} at its first visible sign', () {
        final fixture = loadFixture(name);
        final moments = hintsOf(fixture, HintMode.firstTime);
        final first = starts(moments).firstWhere((m) => m.hint!.key == key);
        final target = first.hint!.targetPassengerId;
        expect(
          first.events.any((e) => triggers(archetype, e, target)),
          isTrue,
          reason: '${first.events}',
        );
        if (target != null) {
          expect(
            fixture.definition.passengers
                .firstWhere((p) => p.passengerId == target)
                .archetype,
            archetype,
          );
        }
        // Once a trip.
        expect(starts(moments).where((m) => m.hint!.key == key), hasLength(1));
      });

      test('${archetype.name} never again once seen', () {
        final moments = hintsOf(
          loadFixture(name),
          HintMode.firstTime,
          seen: {wireOf(archetype)},
        );
        expect(moments.where((m) => m.hint?.key == key), isEmpty);
      });
    }

    test('one at a time, each for the bubble time', () {
      final moments = hintsOf(
        loadFixture('sample__line_gamaa_02_three_stars'),
        HintMode.firstTime,
      );
      final shown = starts(moments);
      expect(shown.length, greaterThanOrEqualTo(2));
      for (var i = 1; i < shown.length; i++) {
        expect(shown[i].tMs - shown[i - 1].tMs, greaterThanOrEqualTo(_minMs));
      }
      // A queued one follows as soon as the first's time is up.
      final queued = [
        for (var i = 1; i < shown.length; i++)
          if (shown[i].tMs - shown[i - 1].tMs < _minMs + engineStep) shown[i],
      ];
      expect(queued, isNotEmpty);
    });
  });

  test('off shows nothing', () {
    for (final name in [
      ..._firstTimeFixtures.values,
      'sample__line_gamaa_02_three_stars',
      'core__fight_at_stop',
    ]) {
      final moments = hintsOf(loadFixture(name), HintMode.off);
      expect(moments.where((m) => m.hint != null), isEmpty, reason: name);
    }
  });
}

/// One engine step, in ms.
const engineStep = 33;
