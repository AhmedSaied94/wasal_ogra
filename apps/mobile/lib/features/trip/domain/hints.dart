// بلية's hints (contracts/trip-view.md "Hints"): by the line's mode, one at
// a time, each for the line's bubble time.
import 'package:content_models/content_models.dart';
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/features/trip/domain/trip_facts.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';
import 'package:wassal/features/trip/domain/view_value.dart';
import 'package:wassal/features/trip/domain/wire.dart';

/// The `always` mode's hint: a station is near and someone is still owed.
const owedHintKey = 'tripHintOwed';

/// The `first_time` hint of [archetype], or null for one without a hint.
String? firstTimeHintKey(Archetype archetype) => switch (archetype) {
  Archetype.sleeper => 'tripHintSleeper',
  Archetype.headphones => 'tripHintHeadphones',
  Archetype.hajja => 'tripHintHajja',
  Archetype.hurry => 'tripHintHurry',
  Archetype.bigNote => 'tripHintBigNote',
  Archetype.student => 'tripHintStudent',
  Archetype.groupPayer => 'tripHintGroupPayer',
  Archetype.chatty => 'tripHintChatty',
  Archetype.falseClaimer => 'tripHintFalseClaimer',
  Archetype.honest => 'tripHintHonest',
  Archetype.regularCustomer => 'tripHintRegularCustomer',
  _ => null,
};

final class HintState extends ViewValue {
  const HintState({
    this.showing,
    this.shownAtMs = 0,
    this.waiting = const [],
    this.explained = const {},
  });

  static const empty = HintState();

  final HintView? showing;
  final int shownAtMs;
  final List<HintView> waiting;

  /// Archetype wire names explained on this device, this trip included.
  final Set<String> explained;

  /// The hints [events] raise at the clock of [state].
  HintState update(
    List<DomainEvent> events, {
    required TripState state,
    required TripFacts facts,
    required Set<String> seen,
  }) => switch (facts.hintMode) {
    HintMode.off => this,
    HintMode.always => _always(events, state),
    HintMode.firstTime => _firstTime(events, state, facts, seen),
  };

  /// The hints of those aboard when the trip opens: a passenger who never
  /// boards on screen is first seen as it opens.
  HintState opened({
    required TripState state,
    required TripFacts facts,
    required Set<String> seen,
  }) => update(
    [
      for (final p in state.passengers)
        if (p.presence == Presence.aboard)
          PassengerBoarded(
            state.tMs,
            passengerId: p.passengerId,
            seatId: p.seatId,
          ),
    ],
    state: state,
    facts: facts,
    seen: seen,
  );

  HintState _always(List<DomainEvent> events, TripState state) {
    var showing = this.showing;
    for (final event in events) {
      switch (event) {
        case StationWarning(:final owed) when owed.isNotEmpty:
          showing = HintView(key: owedHintKey, targetPassengerId: owed.first);
        case StationReached():
          showing = null;
        default:
      }
    }
    final target = showing?.targetPassengerId;
    if (target != null && !(state.passenger(target)?.isOwed ?? false)) {
      showing = null;
    }
    return HintState(showing: showing, shownAtMs: state.tMs);
  }

  HintState _firstTime(
    List<DomainEvent> events,
    TripState state,
    TripFacts facts,
    Set<String> seen,
  ) {
    final explained = {...this.explained, ...seen};
    final waiting = [...this.waiting];
    void meet(Archetype? archetype, String? target) {
      if (archetype == null) return;
      final key = firstTimeHintKey(archetype);
      final wire = wireOf(archetype);
      if (key == null || explained.contains(wire)) return;
      explained.add(wire);
      waiting.add(HintView(key: key, targetPassengerId: target));
    }

    Archetype? archetypeOf(String passengerId) =>
        facts.specs[passengerId]?.archetype;
    Archetype? when(String passengerId, Set<Archetype> types) {
      final archetype = archetypeOf(passengerId);
      return types.contains(archetype) ? archetype : null;
    }

    for (final event in events) {
      switch (event) {
        case PassengerBoarded(:final passengerId):
          meet(
            when(passengerId, const {
              Archetype.sleeper,
              Archetype.headphones,
              Archetype.hurry,
              Archetype.chatty,
            }),
            passengerId,
          );
        case TokenHopStarted(:final from, :final to):
          for (final holder in [from, to]) {
            if (holder.isDriver) continue;
            meet(
              when(holder.passengerId, const {Archetype.hajja}),
              holder.passengerId,
            );
          }
        case FareSent(:final passengerId):
          meet(
            when(passengerId, const {Archetype.bigNote, Archetype.student}),
            passengerId,
          );
        case PassengerSpeaks(:final passengerId, :final slot):
          if (slot == SpeechSlot.paysGroup) {
            meet(when(passengerId, const {Archetype.groupPayer}), passengerId);
          } else if (slot == SpeechSlot.tip) {
            meet(
              when(passengerId, const {Archetype.regularCustomer}),
              passengerId,
            );
          }
        case ClaimRaised():
          meet(Archetype.falseClaimer, null);
        case ExcessReturned(:final passengerId):
          meet(when(passengerId, const {Archetype.honest}), passengerId);
        default:
      }
    }
    var showing = this.showing;
    var shownAtMs = this.shownAtMs;
    if (showing != null && state.tMs - shownAtMs >= facts.bubbleMinMs) {
      showing = null;
    }
    if (showing == null && waiting.isNotEmpty) {
      showing = waiting.removeAt(0);
      shownAtMs = state.tMs;
    }
    return HintState(
      showing: showing,
      shownAtMs: shownAtMs,
      waiting: waiting,
      explained: explained,
    );
  }

  @override
  Map<String, Object?> get fields => {
    'showing': showing,
    'shownAtMs': shownAtMs,
    'waiting': waiting,
    'explained': explained,
  };
}
