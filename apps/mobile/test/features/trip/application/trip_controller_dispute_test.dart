import 'dart:convert';

import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/features/trip/application/trip_controller.dart';
import 'package:wassal/features/trip/data/drift_trip_records.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';

import '../../../helpers/economy.dart';
import '../../../helpers/trip.dart';

// A payment dispute stops the clock until it is answered (tasks.md T067,
// contracts/trip-controller.md "Disputes", FR-032).

/// `event__payment_dispute`'s trip: p1 pays at 1 s, p2 never, and at 5 s
/// they dispute who paid. [twice] adds the same pair again as p3 and p4,
/// disputing at the same moment; [noFights] fails the trip on a fight.
FixedTrip disputeTrip({bool twice = false, bool noFights = false}) {
  final fixture = loadFixture('event__payment_dispute');
  final json = jsonDecode(
    jsonEncode(fixture.definition.toJson()),
  ) as Map<String, Object?>;
  if (noFights) {
    json['rules'] = {
      ...json['rules']! as Map<String, Object?>,
      'no_fights_required': true,
    };
  }
  if (twice) {
    final passengers = (json['passengers']! as List<Object?>)
        .cast<Map<String, Object?>>();
    json['passengers'] = [
      ...passengers,
      {...passengers[0], 'passenger_id': 'p3', 'seat_id': 'A_l'},
      {...passengers[1], 'passenger_id': 'p4', 'seat_id': 'B_r'},
    ];
    final events = (json['events']! as List<Object?>)
        .cast<Map<String, Object?>>();
    json['events'] = [
      ...events,
      {
        ...events[0],
        'passenger_ids': ['p3', 'p4'],
      },
    ];
  }
  return FixedTrip(
    definition: TripDefinition.fromJson(json),
    params: fixture.params,
    seed: fixture.seed,
  );
}

List<Object?> lastCommand(TripController c) =>
    c.engine!.commandLog.last.toJson().sublist(1);

DisputeChoice asked(TripController c) =>
    c.view!.choices.whereType<DisputeChoice>().single;

/// Opens [trip] and runs it until the first dispute.
Future<TripController> untilDispute(TestEconomy economy, FixedTrip trip) async {
  final c = testController(economy, fixed: trip);
  await c.open(trip.definition.tripId);
  runOut(c);
  expect(c.phase, TripPhase.disputeOpen);
  return c;
}

void main() {
  test('a dispute stops the clock until it is answered', () async {
    final economy = await testEconomy();
    final c = await untilDispute(economy, disputeTrip());
    expect(c.engine!.status, TripStatus.paused);
    final tMs = c.engine!.state.tMs;
    advanceMs(c, 1000);
    expect(c.engine!.state.tMs, tMs);
    final dispute = asked(c);
    expect({dispute.a, dispute.b}, {'p1', 'p2'});

    // p1 paid: p2 is caught.
    c.answerDispute('p1');
    expect(lastCommand(c), ['ResolveDispute', dispute.disputeId, 'p1']);
    expect(c.engine!.commandLog.last.tMs, tMs);
    expect(c.phase, TripPhase.running);
    expect(c.engine!.status, TripStatus.running);
    expect(c.view!.choices.whereType<DisputeChoice>(), isEmpty);
    expect(c.engine!.state.counters.caughtLiars, 1);
    advanceMs(c, 33);
    expect(c.engine!.state.tMs, tMs + 33);
  });

  test('two disputes from one step are asked in turn', () async {
    final economy = await testEconomy();
    final c = await untilDispute(economy, disputeTrip(twice: true));
    final first = asked(c);
    expect({first.a, first.b}, {'p1', 'p2'});
    c.answerDispute('p1');
    expect(c.phase, TripPhase.disputeOpen);
    expect(c.engine!.status, TripStatus.paused);
    final second = asked(c);
    expect(second.disputeId, isNot(first.disputeId));
    expect({second.a, second.b}, {'p3', 'p4'});
    c.answerDispute('p3');
    expect(c.phase, TripPhase.running);
    expect(c.engine!.state.counters.caughtLiars, 2);
  });

  test('a wrong answer that fails the trip goes to failed', () async {
    final economy = await testEconomy();
    final c = await untilDispute(economy, disputeTrip(noFights: true));
    // p2 never paid: accusing p1 is a fight.
    c.answerDispute('p2');
    expect(c.engine!.state.counters.fights, 1);
    expect(c.phase, TripPhase.failed);
    expect(c.engine!.status, TripStatus.failed);
  });

  test('the record holds the answer and rebuilds to it', () async {
    final economy = await testEconomy();
    final c = await untilDispute(economy, disputeTrip());
    c.answerDispute('p1');
    advanceMs(c, 330);
    c.dispose();
    await settle();
    final live = c.engine!.state;

    final stored = (await DriftTripRecords(economy.db)
        .load(c.session!.startTxn))!;
    expect(stored.commandJsons.last, contains('ResolveDispute'));

    final rebuilt = testController(economy);
    await rebuilt.open(c.session!.facts.definition.tripId);
    expect(rebuilt.phase, TripPhase.paused);
    expect(
      rebuilt.engine!.state.toJson()..remove('status'),
      live.toJson()..remove('status'),
    );
  });
}
