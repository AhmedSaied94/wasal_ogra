// بلية's coach (specs/012-m07-onboarding/contracts/coach.md, research R14,
// R16–R18): what each tutorial trip teaches, read from the trip's state at
// each moment. Pure: the controller keeps the memory and asks at every
// publish. The only reader of `PassengerState.balance` and `.paidIn` outside
// the engine and the projection (`coach_state_reads_test.dart`).
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/features/trip/domain/presentation_memory.dart';
import 'package:wassal/features/trip/domain/projection.dart';
import 'package:wassal/features/trip/domain/trip_facts.dart';
import 'package:wassal/features/trip/domain/view_value.dart';

/// The steps, one per lesson that has one: lesson `i` teaches `values[i]`;
/// lesson 4 (trip 5) has none in the trip, the fuel lesson coming before it.
enum CoachStepId { fareArrived, giveChange, stopNear, wakeSleeper }

/// What a step points at.
sealed class CoachTarget extends ViewValue {
  const CoachTarget();
}

/// The drawer as a whole.
final class TrayTarget extends CoachTarget {
  const TrayTarget();

  @override
  Map<String, Object?> get fields => const {};
}

/// One cell of the drawer.
final class TrayCellTarget extends CoachTarget {
  const TrayCellTarget(this.denomination);

  final int denomination;

  @override
  Map<String, Object?> get fields => {'denomination': denomination};
}

/// A rider.
final class PassengerTarget extends CoachTarget {
  const PassengerTarget(this.passengerId);

  final String passengerId;

  @override
  Map<String, Object?> get fields => {'passengerId': passengerId};
}

/// The next station's countdown chip.
final class StationCountdownTarget extends CoachTarget {
  const StationCountdownTarget();

  @override
  Map<String, Object?> get fields => const {};
}

/// What بلية says; the words are the app's (`coach*` in `app_ar.arb`).
sealed class CoachLine extends ViewValue {
  const CoachLine();
}

final class FareArrivedLine extends CoachLine {
  const FareArrivedLine();

  @override
  Map<String, Object?> get fields => const {};
}

/// The change [amountPiasters], and the [coin] that pays it [count] times;
/// both null when no single coin does.
final class GiveChangeLine extends CoachLine {
  const GiveChangeLine(this.amountPiasters, {this.coin, this.count});

  final int amountPiasters;
  final int? coin;
  final int? count;

  @override
  Map<String, Object?> get fields => {
    'amountPiasters': amountPiasters,
    'coin': coin,
    'count': count,
  };
}

final class TapRiderLine extends CoachLine {
  const TapRiderLine();

  @override
  Map<String, Object?> get fields => const {};
}

/// The rider gets off at [stationId].
final class StopNearLine extends CoachLine {
  const StopNearLine(this.stationId);

  final String stationId;

  @override
  Map<String, Object?> get fields => {'stationId': stationId};
}

final class WakeSleeperLine extends CoachLine {
  const WakeSleeperLine();

  @override
  Map<String, Object?> get fields => const {};
}

/// The step showing: its [targets] with the active one first, and its line.
final class CoachView extends ViewValue {
  const CoachView({
    required this.lessonStep,
    required this.targets,
    required this.line,
    this.endsOnAnyTap = false,
  });

  final CoachStepId lessonStep;
  final List<CoachTarget> targets;
  final CoachLine line;

  /// The scrim takes the next tap and the step ends (lesson 0).
  final bool endsOnAnyTap;

  CoachTarget get target => targets.first;

  @override
  Map<String, Object?> get fields => {
    'lessonStep': lessonStep,
    'targets': targets,
    'line': line,
    'endsOnAnyTap': endsOnAnyTap,
  };
}

/// One trip run's coaching so far: the steps done, when each showed, and
/// whom it is about. Reset when the trip opens; a rebuilt trip brings an
/// open step back from its state.
final class CoachMemory extends ViewValue {
  const CoachMemory({
    this.done = const {},
    this.shownAtMs = const {},
    this.subjects = const {},
  });

  static const empty = CoachMemory();

  final Set<CoachStepId> done;
  final Map<CoachStepId, int> shownAtMs;

  /// The rider a step is about, fixed when it starts.
  final Map<CoachStepId, String> subjects;

  CoachMemory _started(CoachStepId id, int tMs, String subject) => CoachMemory(
    done: done,
    shownAtMs: {...shownAtMs, id: tMs},
    subjects: {...subjects, id: subject},
  );

  CoachMemory finished(CoachStepId id) => CoachMemory(
    done: {...done, id},
    shownAtMs: shownAtMs,
    subjects: subjects,
  );

  @override
  Map<String, Object?> get fields => {
    'done': done,
    'shownAtMs': shownAtMs,
    'subjects': subjects,
  };
}

/// What the coach reads at one moment.
final class CoachInput {
  const CoachInput({
    required this.lesson,
    required this.state,
    required this.warning,
    required this.memory,
    required this.bubbleMinMs,
    required this.destinations,
  });

  /// The trip's index in the tutorial, 0 to 4.
  final int lesson;
  final TripState state;

  /// The last station warning, for the stop that is near (lesson 2).
  final WarningMemory? warning;
  final CoachMemory memory;

  /// `trip_bubble_min_ms_<line>`: lesson 0's time, lesson 2's countdown.
  final int bubbleMinMs;

  /// Each rider's drop-off station.
  final Map<String, String> destinations;
}

/// The step to show, if any, and the memory after this moment.
typedef CoachStep = ({CoachView? view, CoachMemory memory});

abstract final class TutorialCoach {
  /// The step of [CoachInput.lesson] at this moment: an open step whose end
  /// now holds is done; otherwise it shows, or a step whose start holds
  /// begins. A step in `done` never shows again.
  static CoachStep step(CoachInput input) {
    var memory = input.memory;
    final lesson = input.lesson;
    if (lesson < 0 || lesson >= CoachStepId.values.length) {
      return (view: null, memory: memory);
    }
    final id = CoachStepId.values[lesson];
    if (memory.done.contains(id)) return (view: null, memory: memory);
    var subject = memory.subjects[id];
    if (subject != null) {
      if (_ended(id, subject, input)) {
        return (view: null, memory: memory.finished(id));
      }
    } else {
      subject = _starting(id, input);
      if (subject == null) return (view: null, memory: memory);
      memory = memory._started(id, input.state.tMs, subject);
    }
    final shownAt = memory.shownAtMs[id] ?? input.state.tMs;
    return (view: _view(id, subject, shownAt, input), memory: memory);
  }

  /// A tap the scrim took: it ends a step that ends on any tap.
  static CoachMemory tapped(CoachMemory memory, CoachView? view) =>
      view != null && view.endsOnAnyTap
      ? memory.finished(view.lessonStep)
      : memory;

  /// The rider the step would be about, when its start holds now.
  static String? _starting(CoachStepId id, CoachInput input) {
    final state = input.state;
    for (final p in state.passengers) {
      final starts = switch (id) {
        CoachStepId.fareArrived => p.paidIn > 0,
        CoachStepId.giveChange => _owed(state, p),
        CoachStepId.stopNear =>
          _owed(state, p) && isNearStop(state, input.warning, p),
        CoachStepId.wakeSleeper =>
          p.presence == Presence.aboard && p.alertness == Alertness.asleep,
      };
      if (starts) return p.passengerId;
    }
    return null;
  }

  static bool _ended(CoachStepId id, String subject, CoachInput input) {
    final state = input.state;
    final p = state.passenger(subject);
    if (p == null || p.presence != Presence.aboard) {
      // Lesson 0 is about the drawer, not the rider who paid.
      if (id != CoachStepId.fareArrived) return true;
    }
    return switch (id) {
      CoachStepId.fareArrived =>
        state.tMs - input.memory.shownAtMs[id]! >= input.bubbleMinMs,
      CoachStepId.giveChange => !_stillOwed(state, p!),
      CoachStepId.stopNear =>
        !_stillOwed(state, p!) || _reached(state, input.destinations[subject]),
      CoachStepId.wakeSleeper => p!.alertness != Alertness.asleep,
    };
  }

  static CoachView _view(
    CoachStepId id,
    String subject,
    int shownAtMs,
    CoachInput input,
  ) => switch (id) {
    CoachStepId.fareArrived => const CoachView(
      lessonStep: CoachStepId.fareArrived,
      targets: [TrayTarget()],
      line: FareArrivedLine(),
      endsOnAnyTap: true,
    ),
    CoachStepId.giveChange => _change(id, subject, input.state),
    CoachStepId.stopNear =>
      input.state.tMs - shownAtMs < input.bubbleMinMs
          ? CoachView(
              lessonStep: id,
              targets: const [StationCountdownTarget()],
              line: StopNearLine(input.destinations[subject] ?? ''),
            )
          : _change(id, subject, input.state),
    CoachStepId.wakeSleeper => CoachView(
      lessonStep: id,
      targets: [PassengerTarget(subject)],
      line: const WakeSleeperLine(),
    ),
  };

  /// The coins for [subject]'s change, then the rider.
  static CoachView _change(CoachStepId id, String subject, TripState state) {
    final owed = state.passenger(subject)!.balance;
    final rider = PassengerTarget(subject);
    if (state.hand.total >= owed) {
      return CoachView(
        lessonStep: id,
        targets: [rider],
        line: const TapRiderLine(),
      );
    }
    final coin = coinFor(owed, state);
    return CoachView(
      lessonStep: id,
      targets: [
        if (coin == null) const TrayTarget() else TrayCellTarget(coin),
        rider,
      ],
      line: GiveChangeLine(
        owed,
        coin: coin,
        count: coin == null ? null : owed ~/ coin,
      ),
    );
  }

  /// The largest coin that pays [owed] alone, with enough of it between the
  /// drawer and the hand; null when none does.
  static int? coinFor(int owed, TripState state) {
    for (final d in trayDenominations.reversed) {
      if (owed % d != 0) continue;
      final have = (state.tray.counts[d] ?? 0) + (state.hand.counts[d] ?? 0);
      if (have >= owed ~/ d) return d;
    }
    return null;
  }

  /// Aboard, owed, their fare arrived, and no change on its way to them.
  static bool _owed(TripState state, PassengerState p) =>
      p.presence == Presence.aboard && p.paidIn > 0 && _stillOwed(state, p);

  static bool _stillOwed(TripState state, PassengerState p) =>
      p.isOwed &&
      !state.tokens.any(
        (t) =>
            t.kind == TokenKind.change &&
            t.target == Holder.passenger(p.passengerId),
      );

  static bool _reached(TripState state, String? stationId) {
    final index = state.schedule.indexWhere((s) => s.stationId == stationId);
    return index >= 0 && index < state.nextStationIndex;
  }
}
