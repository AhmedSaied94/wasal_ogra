// Refusals at start (data-model.md "Validation", FR-003): one case per code,
// every problem reported at once, and every shipped trip accepted.
import 'dart:convert';
import 'dart:io';

import 'package:content_models/content_models.dart';
import 'package:test/test.dart';
import 'package:trip_engine/src/validation.dart';
import 'package:trip_engine/trip_engine.dart';

import '../support/builders.dart';
import '../support/default_params.dart';

TripBuilder _base() => TripBuilder()
  ..station('kobri', 30)
  ..station('gamaa', 60)
  ..passenger('p1', seat: 'A_r', dest: 'kobri', payment: [1000])
  ..passenger('p2', seat: 'B_m', dest: 'gamaa', payment: [1000]);

List<Refusal> _refusals(
  TripDefinition definition, {
  TripParams? params,
  int? seed,
}) => validate(definition, params ?? defaultParams(), seed ?? definition.seed);

List<(String, String)> _codes(
  TripDefinition definition, {
  TripParams? params,
  int? seed,
}) => [
  for (final refusal in _refusals(definition, params: params, seed: seed))
    (refusal.code.wire, refusal.path),
];

TripDefinition _json(
  TripDefinition definition,
  void Function(Map<String, Object?> json) edit,
) {
  final json =
      jsonDecode(jsonEncode(definition.toJson())) as Map<String, Object?>;
  edit(json);
  return TripDefinition.fromJson(json);
}

List<Map<String, Object?>> _list(Map<String, Object?> json, String key) =>
    (json[key]! as List<Object?>).cast<Map<String, Object?>>();

void main() {
  test('a valid trip has no refusals', () {
    expect(_refusals(_base().build()), isEmpty);
  });

  test('bad_seed', () {
    expect(_codes(_base().build(), seed: 0), [('bad_seed', 'seed')]);
    expect(_codes(_base().build(), seed: 0x100000000), [('bad_seed', 'seed')]);
    expect(_codes(_base().build(), seed: 0xFFFFFFFF), isEmpty);
  });

  test('bad_params', () {
    expect(
      _codes(
        _base().build(),
        params: paramsWith({'rep_revive_to': 0, 'trip_hop_ms': 1}),
      ),
      unorderedEquals([
        ('bad_params', 'params.rep_revive_to'),
        ('bad_params', 'params.trip_hop_ms'),
      ]),
    );
  });

  test('duplicate_id', () {
    final seats = _json(
      _base().build(),
      (json) => _list(json, 'seats')[2]['seat_id'] = 'A_r',
    );
    expect(_codes(seats), contains(('duplicate_id', r'$.seats[2].seat_id')));
    final stations = _json(
      _base().build(),
      (json) => _list(json, 'stations')[1]['station_id'] = 'kobri',
    );
    expect(
      _codes(stations),
      contains(('duplicate_id', r'$.stations[1].station_id')),
    );
    final passengers =
        (_base()..passenger('p1', seat: 'C_l', dest: 'gamaa', payment: [1000]))
            .build();
    expect(_codes(passengers), [
      ('duplicate_id', r'$.passengers[2].passenger_id'),
    ]);
  });

  test('unknown_seat', () {
    final definition =
        (_base()..passenger('p3', seat: 'D_r', dest: 'gamaa', payment: [1000]))
            .build();
    expect(_codes(definition), [('unknown_seat', r'$.passengers[2].seat_id')]);
  });

  test('unknown_station', () {
    final dest =
        (_base()..passenger('p3', seat: 'C_r', dest: 'souq', payment: [1000]))
            .build();
    expect(_codes(dest), [
      ('unknown_station', r'$.passengers[2].dest_station_id'),
    ]);
    final board =
        (_base()..passenger(
              'p3',
              seat: 'C_r',
              dest: 'gamaa',
              board: 'souq',
              payment: [1000],
            ))
            .build();
    expect(_codes(board), [
      ('unknown_station', r'$.passengers[2].board_station_id'),
    ]);
  });

  test('stations_out_of_order', () {
    final definition =
        (TripBuilder()
              ..station('kobri', 30)
              ..station('gamaa', 30)
              ..passenger('p1', seat: 'A_r', dest: 'kobri', payment: [1000]))
            .build();
    expect(_codes(definition), [
      ('stations_out_of_order', r'$.stations[1].at_seconds'),
    ]);
  });

  test('board_after_dest', () {
    final definition =
        (_base()..passenger(
              'p3',
              seat: 'C_r',
              dest: 'kobri',
              board: 'gamaa',
              payment: [1000],
            ))
            .build();
    expect(_codes(definition), [
      ('board_after_dest', r'$.passengers[2].board_station_id'),
    ]);
    final same =
        (_base()..passenger(
              'p3',
              seat: 'C_r',
              dest: 'kobri',
              board: 'kobri',
              payment: [1000],
            ))
            .build();
    expect(_codes(same), [
      ('board_after_dest', r'$.passengers[2].board_station_id'),
    ]);
  });

  test('seat_taken_at_start', () {
    final taken =
        (_base()..passenger('p3', seat: 'A_r', dest: 'gamaa', payment: [1000]))
            .build();
    expect(_codes(taken), [
      ('seat_taken_at_start', r'$.passengers[2].seat_id'),
    ]);
    final later =
        (_base()..passenger(
              'p3',
              seat: 'A_r',
              dest: 'gamaa',
              board: 'kobri',
              payment: [1000],
            ))
            .build();
    expect(_codes(later), isEmpty);
  });

  test('unknown_passenger', () {
    final definition =
        (_base()..event(EventId.dropMeHere, 10, passengers: ['p9'])).build();
    expect(_codes(definition), [
      ('unknown_passenger', r'$.events[0].passenger_ids[0]'),
    ]);
  });

  group('group_mismatch', () {
    TripBuilder group() => _base()
      ..passenger(
        'p3',
        archetype: Archetype.groupPayer,
        seat: 'C_r',
        dest: 'gamaa',
        payment: [5000],
        group: 'g1',
        groupSize: 3,
      )
      ..passenger(
        'p4',
        seat: 'C_m',
        dest: 'gamaa',
        payment: [1000],
        group: 'g1',
        groupSize: 3,
      );

    test('a valid group', () {
      expect(_codes(group().build()), isEmpty);
    });
    test('sizes disagree', () {
      final definition =
          (group()..passenger(
                'p5',
                seat: 'C_l',
                dest: 'gamaa',
                payment: [1000],
                group: 'g1',
                groupSize: 2,
              ))
              .build();
      expect(_codes(definition), [
        ('group_mismatch', r'$.passengers[4].group_size'),
      ]);
    });
    test('more members than the size', () {
      final definition =
          (group()
                ..passenger(
                  'p5',
                  seat: 'C_l',
                  dest: 'gamaa',
                  payment: [1000],
                  group: 'g1',
                  groupSize: 3,
                )
                ..passenger(
                  'p6',
                  seat: 'B_r',
                  dest: 'gamaa',
                  payment: [1000],
                  group: 'g1',
                  groupSize: 3,
                ))
              .build();
      expect(_codes(definition), [
        ('group_mismatch', r'$.passengers[5].group_id'),
      ]);
    });
    test('no group_payer, or two', () {
      final none =
          (_base()..passenger(
                'p3',
                seat: 'C_r',
                dest: 'gamaa',
                payment: [1000],
                group: 'g1',
                groupSize: 2,
              ))
              .build();
      expect(_codes(none), [('group_mismatch', r'$.passengers[2].group_id')]);
      final two =
          (group()..passenger(
                'p5',
                archetype: Archetype.groupPayer,
                seat: 'C_l',
                dest: 'gamaa',
                payment: [5000],
                group: 'g1',
                groupSize: 3,
              ))
              .build();
      expect(_codes(two), [('group_mismatch', r'$.passengers[4].archetype')]);
    });
    test('a group payer without a group, or a size without a group', () {
      final payer =
          (_base()..passenger(
                'p3',
                archetype: Archetype.groupPayer,
                seat: 'C_r',
                dest: 'gamaa',
                payment: [5000],
              ))
              .build();
      expect(_codes(payer), [('group_mismatch', r'$.passengers[2].group_id')]);
      final size =
          (_base()..passenger(
                'p3',
                seat: 'C_r',
                dest: 'gamaa',
                payment: [1000],
                groupSize: 2,
              ))
              .build();
      expect(_codes(size), [('group_mismatch', r'$.passengers[2].group_size')]);
      final missing =
          (group()..passenger(
                'p5',
                seat: 'C_l',
                dest: 'gamaa',
                payment: [1000],
                group: 'g1',
              ))
              .build();
      expect(_codes(missing), [
        ('group_mismatch', r'$.passengers[4].group_size'),
      ]);
    });
  });

  test('unsupported_archetype', () {
    final definition =
        (_base()..passenger(
              'p3',
              archetype: Archetype.dodger,
              seat: 'C_r',
              dest: 'gamaa',
              payment: [1000],
            ))
            .build();
    expect(_codes(definition), [
      ('unsupported_archetype', r'$.passengers[2].archetype'),
    ]);
  });

  test('unsupported_event', () {
    final definition = (_base()..event(EventId.traffic, 10, seconds: 5))
        .build();
    final refusals = validateWith(
      definition,
      defaultParams(),
      1,
      events: {EventId.bump},
    );
    expect(
      [for (final r in refusals) (r.code.wire, r.path)],
      [('unsupported_event', r'$.events[0].event_id')],
    );
  });

  group('event_param', () {
    List<(String, String)> eventCodes(void Function(TripBuilder builder) add) {
      final builder = _base()
        ..passenger(
          'p3',
          archetype: Archetype.groupPayer,
          seat: 'C_r',
          dest: 'gamaa',
          payment: [5000],
          group: 'g1',
          groupSize: 2,
        )
        ..passenger(
          'p4',
          seat: 'C_m',
          dest: 'gamaa',
          payment: [1000],
          group: 'g1',
          groupSize: 2,
        );
      add(builder);
      return _codes(builder.build());
    }

    test('forbidden parameters', () {
      expect(eventCodes((b) => b.event(EventId.bump, 5, seconds: 3)), [
        ('event_param', r'$.events[0].seconds'),
      ]);
      expect(eventCodes((b) => b.event(EventId.bump, 5, station: 'kobri')), [
        ('event_param', r'$.events[0].station_id'),
      ]);
    });
    test('missing required parameters', () {
      expect(eventCodes((b) => b.event(EventId.traffic, 5)), [
        ('event_param', r'$.events[0].seconds'),
      ]);
      expect(eventCodes((b) => b.event(EventId.fareIncrease, 5)), [
        ('event_param', r'$.events[0].amount_piasters'),
      ]);
    });
    test('integer bounds', () {
      expect(eventCodes((b) => b.event(EventId.traffic, 5, seconds: 0)), [
        ('event_param', r'$.events[0].seconds'),
      ]);
      expect(eventCodes((b) => b.event(EventId.openRoad, 5, seconds: 61)), [
        ('event_param', r'$.events[0].seconds'),
      ]);
      expect(
        eventCodes((b) => b.event(EventId.traffic, 5, seconds: 60)),
        isEmpty,
      );
      expect(eventCodes((b) => b.event(EventId.fareIncrease, 5, amount: 0)), [
        ('event_param', r'$.events[0].amount_piasters'),
      ]);
    });
    test('list lengths', () {
      expect(
        eventCodes(
          (b) => b.event(EventId.dropMeHere, 5, passengers: ['p1', 'p2']),
        ),
        [('event_param', r'$.events[0].passenger_ids')],
      );
      expect(
        eventCodes(
          (b) => b.event(EventId.paymentDispute, 5, passengers: ['p1']),
        ),
        [('event_param', r'$.events[0].passenger_ids')],
      );
    });
    test('one_of', () {
      expect(
        eventCodes(
          (b) => b.event(
            EventId.changeRequest,
            5,
            passengers: ['p1'],
            amount: 500,
          ),
        ),
        [('event_param', r'$.events[0].amount_piasters')],
      );
      expect(
        eventCodes(
          (b) => b.event(
            EventId.changeRequest,
            5,
            passengers: ['p1'],
            amount: 5000,
          ),
        ),
        isEmpty,
      );
    });
    test('no_group_members', () {
      expect(
        eventCodes(
          (b) => b.event(EventId.paymentDispute, 5, passengers: ['p1', 'p4']),
        ),
        [('event_param', r'$.events[0].passenger_ids[1]')],
      );
      expect(
        eventCodes(
          (b) => b.event(EventId.paymentDispute, 5, passengers: ['p1', 'p2']),
        ),
        isEmpty,
      );
    });
  });

  test('pickup_conflict', () {
    final twice =
        (_base()
              ..passenger('p3', seat: 'C_r', dest: 'gamaa', payment: [1000])
              ..event(EventId.roadsidePickup, 5, passengers: ['p3'])
              ..event(EventId.roadsidePickup, 10, passengers: ['p3']))
            .build();
    expect(_codes(twice), [
      ('pickup_conflict', r'$.events[1].passenger_ids[0]'),
    ]);
    final boarding =
        (_base()
              ..passenger(
                'p3',
                seat: 'C_r',
                dest: 'gamaa',
                board: 'kobri',
                payment: [1000],
              )
              ..event(EventId.roadsidePickup, 5, passengers: ['p3']))
            .build();
    expect(_codes(boarding), [
      ('pickup_conflict', r'$.events[0].passenger_ids[0]'),
    ]);
  });

  test('every problem is reported at once, with paths and messages', () {
    final definition =
        (_base()
              ..passenger(
                'p3',
                archetype: Archetype.bagsLady,
                seat: 'D_l',
                dest: 'souq',
                payment: [1000],
              )
              ..event(EventId.bump, 5, seconds: 2))
            .build();
    final refusals = _refusals(definition, seed: 0);
    expect(refusals.map((r) => r.code.wire).toSet(), {
      'bad_seed',
      'unknown_seat',
      'unknown_station',
      'unsupported_archetype',
      'event_param',
    });
    expect(refusals.every((r) => r.message.isNotEmpty), isTrue);
  });

  test('TripEngine.start throws TripRefused with every refusal', () {
    final definition =
        (_base()..passenger('p3', seat: 'D_l', dest: 'souq', payment: [1000]))
            .build();
    expect(
      () => TripEngine.start(definition, defaultParams()),
      throwsA(
        isA<TripRefused>().having((e) => e.refusals, 'refusals', hasLength(2)),
      ),
    );
  });

  final shipped =
      [
            ...Directory('../../content/examples/sample/trips')
                .listSync(recursive: true),
            ...Directory('../../content/examples/valid/trip').listSync(),
          ]
          .whereType<File>()
          .where((file) => file.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  for (final file in shipped) {
    test('${file.path} is accepted', () {
      final definition = TripDefinition.fromJson(
        jsonDecode(file.readAsStringSync()) as Map<String, dynamic>,
      );
      expect(
        _refusals(definition, params: defaultParams(definition.lineId)),
        isEmpty,
      );
    });
  }
}
