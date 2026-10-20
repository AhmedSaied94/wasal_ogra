// «حد معاه فكة؟» (rules.md §3 step 2.6, §4.9, §14.1): a note goes out and its
// break-down comes back trip_break_delay_ms (1.5 s) later.
import 'package:content_models/content_models.dart';
import 'package:test/test.dart';
import 'package:trip_engine/trip_engine.dart';

import '../support/builders.dart';
import '../support/default_params.dart';
import '../support/scripts.dart';

TripBuilder _trip(Map<int, int> tray, {int maxBreaks = 2}) => TripBuilder()
  ..station('gamaa', 30)
  ..passenger(
    'p1',
    seat: 'A_r',
    dest: 'gamaa',
    payment: [500, 100, 100],
    paysAt: 1,
  )
  ..tray(tray)
  ..rules(maxBreakRequests: maxBreaks);

void main() {
  for (final note in [1000, 2000, 5000, 10000, 20000]) {
    test('$note comes back as its table row 1.5 s later', () {
      final engine = startTrip(_trip({note: 1, 50: 1}).build());
      final total = engine.state.tray.total;
      final request = engine.ok(RequestBreak(note));
      final requested = eventsOf<BreakRequested>(request).single;
      expect((requested.denomination, requested.completesAtMs), (note, 1500));
      expect(engine.state.tray.total, total - note);
      expect(engine.state.breaksUsed, 1);
      expect(eventsOf<BreakCompleted>(engine.stepTo(1485)), isEmpty);
      final done = eventsOf<BreakCompleted>(engine.step()).single;
      expect(done.tMs, 1518);
      expect(done.pieces.total, note);
      expect(done.pieces.count(note), 0);
      expect(engine.state.tray.total, total);
      expect(engine.state.pendingBreaks, isEmpty);
    });
  }

  test('a 10000 note gives 5000, 2000×2, 500, 100×4 and 50×2', () {
    final engine = startTrip(_trip({10000: 1}).build())
      ..ok(const RequestBreak(10000))
      ..stepTo(1518);
    expect(engine.state.tray.toJson(), {
      '50': 2,
      '100': 4,
      '500': 1,
      '2000': 2,
      '5000': 1,
    });
  });

  test('a note the tray lacks is tray_empty', () {
    startTrip(_trip({1000: 1}).build())
        .rejects(const RequestBreak(2000), RejectionCode.trayEmpty);
  });

  test('beyond max_break_requests is break_limit', () {
    final engine = startTrip(_trip({1000: 3}).build())
      ..ok(const RequestBreak(1000))
      ..ok(const RequestBreak(1000));
    engine.rejects(const RequestBreak(1000), RejectionCode.breakLimit);
  });

  test('a note below trip_break_min_piasters is break_limit', () {
    startTrip(_trip({500: 2}).build())
        .rejects(const RequestBreak(500), RejectionCode.breakLimit);
  });

  test('a value that is not a denomination is bad_argument', () {
    startTrip(_trip({1000: 1}).build())
        .rejects(const RequestBreak(1500), RejectionCode.badArgument);
  });

  test('a note with no table row is break_limit', () {
    final engine = startTrip(
      _trip({500: 2}).build(),
      params: paramsWith({'trip_break_min_piasters': 500}),
    );
    engine.rejects(const RequestBreak(500), RejectionCode.breakLimit);
  });

  test('a break completes while a choice is open', () {
    final engine = startTrip(
      (_trip({1000: 1})..passenger(
            'p2',
            seat: 'A_m',
            dest: 'gamaa',
            payment: [1000],
            paysAt: 1,
            archetype: Archetype.falseClaimer,
          ))
          .build(),
    )..stepTo(1023);
    expect(engine.state.claims.keys, ['p2']);
    engine.ok(const RequestBreak(1000));
    final events = engine.stepTo(2541);
    expect(eventsOf<BreakCompleted>(events), hasLength(1));
    expect(engine.state.claims.keys, ['p2']);
  });
}
