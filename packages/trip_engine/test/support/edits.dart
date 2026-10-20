// Test hooks that set up a situation outside the rules: a passenger asleep,
// a reputation, a counter (research R16 "builder hooks").
import 'package:trip_engine/src/engine.dart';
import 'package:trip_engine/src/model/passenger.dart';
import 'package:trip_engine/trip_engine.dart';

int _index(TripEngine engine, String passengerId) =>
    engine.state.passengers.indexWhere((p) => p.passengerId == passengerId);

/// Sets [passengerId]'s alertness, with no timer.
void setAlertness(TripEngine engine, String passengerId, Alertness alertness) {
  final i = _index(engine, passengerId);
  engine.debugEdit(
    (tx) => tx.setPassenger(
      i,
      tx
          .passenger(i)
          .copyWith(alertness: alertness, alertUntilMs: null, taps: 0),
    ),
  );
}

void setReputation(TripEngine engine, int reputation) =>
    engine.debugEdit((tx) => tx.reputation = reputation);

void editCounters(
  TripEngine engine,
  Counters Function(Counters counters) edit,
) => engine.debugEdit((tx) => tx.counters = edit(tx.counters));

void addMistake(TripEngine engine, Mistake mistake) =>
    engine.debugEdit((tx) => tx.addMistake(mistake));

void setTrafficActive(TripEngine engine, bool active) =>
    engine.debugEdit((tx) => tx.trafficActive = active);
