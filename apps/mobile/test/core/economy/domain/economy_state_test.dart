import 'dart:convert';

import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/core/economy/domain/economy_state.dart';
import 'package:wassal/core/economy/domain/txn_id.dart';

final _a = TxnId.parse('0192f3a1-7b2c-7d4e-8f00-000000000001');
final _b = TxnId.parse('0192f3a1-7b2c-7d4e-8f00-000000000002');

/// A state with every field set.
EconomyState fullState() => EconomyState(
  jenehat: 120,
  bonat: 7,
  fuel: const FuelState(liters: 3, countedFromMs: 1000, unlimitedUntilMs: 9000),
  inventory: {BoosterId.changeBag: 2, BoosterId.trafficJam: 1},
  ownership: {
    (SkuKind.item, 'salon.nish'): Owned(
      kind: SkuKind.item,
      variantId: 'classic',
      acquiredAtMs: 500,
      acquiredBy: _a,
    ),
    (SkuKind.vehicle, 'micro_old'): Owned(
      kind: SkuKind.vehicle,
      acquiredAtMs: 600,
      acquiredBy: _b,
    ),
  },
  progress: {
    'line_hay.01': const TripProgress(
      bestStars: 2,
      bestTimeMs: 80000,
      plays: 3,
      firstCompletedAtMs: 700,
    ),
    'line_hay.02': const TripProgress(bestStars: 0, plays: 1),
  },
  unfinished: UnfinishedTrip(
    startTxn: _b,
    tripId: 'line_hay.02',
    contentVersion: 1,
    maxEarningsJenehat: 30,
    startedAtMs: 800,
    revived: true,
    trafficJamAds: 1,
  ),
  lastResult: LastResult(
    startTxn: _a,
    outcome: TripOutcome.finished,
    earningsJenehat: 15,
    doubled: true,
  ),
  displayName: 'Hamada',
  tutorialGranted: true,
  scenesSeen: const {
    'ch1_first_job': {'the_stand', 'opening'},
  },
  requestsClaimed: const {'req_nish_crystal'},
);

Map<String, Object?> _json(EconomyState state) =>
    (jsonDecode(canonicalJson(state.toJson())) as Map<String, dynamic>)
        .cast<String, Object?>();

void main() {
  test('a new player has a full tank, counted from the first open', () {
    final state = EconomyState.newPlayer(fuelMax: 5, nowMs: 1234);
    expect(state.jenehat, 0);
    expect(state.bonat, 0);
    expect(state.fuel, const FuelState(liters: 5, countedFromMs: 1234));
    expect(state.inventory, isEmpty);
    expect(state.ownership, isEmpty);
    expect(state.progress, isEmpty);
    expect(state.unfinished, isNull);
    expect(state.lastResult, isNull);
  });

  test('toJson is canonical and fromJson round-trips every field', () {
    final state = fullState();
    final text = canonicalJson(state.toJson());
    expect(text, isNot(contains(' ')));
    expect(EconomyState.fromJson(jsonDecode(text)), state);
    expect(
      canonicalJson(EconomyState.fromJson(jsonDecode(text)).toJson()),
      text,
    );
    final fresh = EconomyState.newPlayer(fuelMax: 5, nowMs: 1);
    expect(EconomyState.fromJson(_json(fresh)), fresh);
  });

  test('the name and the tutorial grant round-trip (M07 data-model.md)', () {
    final named = EconomyState.newPlayer(
      fuelMax: 5,
      nowMs: 1,
    ).copyWith(displayName: () => 'Hamada', tutorialGranted: true);
    final json = _json(named);
    expect(json['display_name'], 'Hamada');
    expect(json['tutorial_granted'], isTrue);
    expect(EconomyState.fromJson(json), named);
    expect(EconomyState.fromJson(json).displayName, 'Hamada');
    expect(EconomyState.fromJson(json).tutorialGranted, isTrue);
  });

  test('a v3 base without them reads as no name and no grant', () {
    final v3 = EconomyState.newPlayer(fuelMax: 5, nowMs: 1);
    final json = _json(v3);
    expect(json.keys, isNot(contains('display_name')));
    expect(json.keys, isNot(contains('tutorial_granted')));
    final read = EconomyState.fromJson(json);
    expect(read.displayName, isNull);
    expect(read.tutorialGranted, isFalse);
  });

  test('copyWith clears the name', () {
    final named = fullState();
    expect(named.copyWith(displayName: () => null).displayName, isNull);
    expect(named.copyWith(jenehat: 1).displayName, 'Hamada');
  });

  test('equality looks at every field', () {
    expect(fullState(), fullState());
    expect(fullState().hashCode, fullState().hashCode);
    expect(fullState().copyWith(jenehat: 1), isNot(fullState()));
    expect(
      fullState().copyWith(inventory: {BoosterId.changeBag: 2}),
      isNot(fullState()),
    );
    expect(fullState().copyWith(unfinished: () => null), isNot(fullState()));
    expect(fullState().copyWith(displayName: () => 'x'), isNot(fullState()));
    expect(fullState().copyWith(tutorialGranted: false), isNot(fullState()));
  });

  group('the story state (M10)', () {
    test('newPlayer starts both empty', () {
      final state = EconomyState.newPlayer(fuelMax: 5, nowMs: 1);
      expect(state.scenesSeen, isEmpty);
      expect(state.requestsClaimed, isEmpty);
    });

    test('the canonical JSON writes them sorted, and reads them back', () {
      final json = _json(
        EconomyState.newPlayer(fuelMax: 5, nowMs: 1).copyWith(
          scenesSeen: {
            'ch4_salon': {'family_visit'},
            'ch1_first_job': {'the_stand', 'opening'},
          },
          requestsClaimed: {'req_b', 'req_a'},
        ),
      );
      expect(json['scenes_seen'], {
        'ch1_first_job': ['opening', 'the_stand'],
        'ch4_salon': ['family_visit'],
      });
      expect(json['requests_claimed'], ['req_a', 'req_b']);
      final back = EconomyState.fromJson(json);
      expect(back.scenesSeen['ch1_first_job'], {'opening', 'the_stand'});
      expect(back.requestsClaimed, {'req_a', 'req_b'});
    });

    test('a base from before M10 reads as empty', () {
      final json = _json(EconomyState.newPlayer(fuelMax: 5, nowMs: 1))
        ..remove('scenes_seen')
        ..remove('requests_claimed');
      final read = EconomyState.fromJson(json);
      expect(read.scenesSeen, isEmpty);
      expect(read.requestsClaimed, isEmpty);
    });

    test('equality looks at both', () {
      final base = EconomyState.newPlayer(fuelMax: 5, nowMs: 1);
      expect(
        base.copyWith(
          scenesSeen: {
            'ch1_first_job': {'opening'},
          },
        ),
        isNot(base),
      );
      expect(base.copyWith(requestsClaimed: {'req_a'}), isNot(base));
      expect(
        base
            .copyWith(
              scenesSeen: {
                'ch1_first_job': {'opening'},
              },
            )
            .hashCode,
        isNot(base.hashCode),
      );
    });

    test('both are unmodifiable', () {
      final state = EconomyState.newPlayer(fuelMax: 5, nowMs: 1).copyWith(
        scenesSeen: {
          'ch1_first_job': {'opening'},
        },
        requestsClaimed: {'req_a'},
      );
      expect(() => state.scenesSeen['x'] = const {}, throwsUnsupportedError);
      expect(() => state.requestsClaimed.add('y'), throwsUnsupportedError);
      expect(
        () => state.scenesSeen['ch1_first_job']!.add('z'),
        throwsUnsupportedError,
      );
    });
  });

  test('a zero inventory count is dropped', () {
    final state = fullState().copyWith(
      inventory: {BoosterId.changeBag: 0, BoosterId.wakeAll: 1},
    );
    expect(state.inventory, {BoosterId.wakeAll: 1});
  });

  group('fromJson refuses', () {
    void refuses(String what, void Function(Map<String, Object?> json) edit) {
      test(what, () {
        final json = _json(fullState());
        edit(json);
        expect(
          () => EconomyState.fromJson(jsonDecode(jsonEncode(json))),
          throwsFormatException,
        );
      });
    }

    Map<String, Object?> sub(Map<String, Object?> json, String key) =>
        json[key]! as Map<String, Object?>;

    refuses('a non-integer amount', (j) => j['jenehat'] = 1.5);
    refuses('a negative jenehat', (j) => j['jenehat'] = -1);
    refuses('a negative bonat', (j) => j['bonat'] = -1);
    refuses('negative liters', (j) => sub(j, 'fuel')['liters'] = -1);
    refuses('a negative inventory count', (j) {
      sub(j, 'inventory')['change_bag'] = -1;
    });
    refuses('a booster outside the four', (j) {
      sub(j, 'inventory')['refuel_full'] = 1;
    });
    refuses('an ownership kind outside the three', (j) {
      (j['ownership']! as List<Object?>).add({
        'kind': 'booster',
        'sku_id': 'x',
        'acquired_at_ms': 1,
        'acquired_by': _a.value,
      });
    });
    refuses('an item with no variant', (j) {
      ((j['ownership']! as List<Object?>).first! as Map<String, Object?>)
          .remove('variant_id');
    });
    refuses('best_stars above 3', (j) {
      (sub(j, 'progress')['line_hay.01']!
              as Map<String, Object?>)['best_stars'] =
          4;
    });
    refuses('best_stars below 0', (j) {
      (sub(j, 'progress')['line_hay.01']!
              as Map<String, Object?>)['best_stars'] =
          -1;
    });
    refuses('traffic_jam_ads above 1', (j) {
      sub(j, 'unfinished')['traffic_jam_ads'] = 2;
    });
    refuses('an unknown key', (j) => j['level'] = 3);
    refuses('a bad txn id', (j) => sub(j, 'last_result')['start_txn'] = 'x');
    refuses('an unknown outcome', (j) {
      sub(j, 'last_result')['outcome'] = 'won';
    });
  });

  test('Owned without its operation round-trips (M06 research R12)', () {
    final state = fullState().copyWith(
      ownership: {
        (SkuKind.item, 'salon.nish'): Owned(
          kind: SkuKind.item,
          variantId: 'classic',
          acquiredAtMs: 500,
        ),
        (SkuKind.vehicle, 'micro_old'): Owned(
          kind: SkuKind.vehicle,
          acquiredAtMs: 600,
        ),
      },
    );
    final json = _json(state);
    for (final row in json['ownership']! as List<Object?>) {
      expect(
        (row! as Map<String, Object?>).containsKey('acquired_by'),
        isFalse,
      );
    }
    final back = EconomyState.fromJson(json);
    expect(back, state);
    expect(back.ownership.values.map((o) => o.acquiredBy), [null, null]);
    expect(
      Owned(kind: SkuKind.vehicle, acquiredAtMs: 600),
      isNot(Owned(kind: SkuKind.vehicle, acquiredAtMs: 600, acquiredBy: _b)),
    );
  });

  test('Owned requires a variant for an item, and only for an item', () {
    expect(
      () => Owned(kind: SkuKind.item, acquiredAtMs: 1, acquiredBy: _a),
      throwsArgumentError,
    );
    expect(
      () => Owned(
        kind: SkuKind.vehicle,
        variantId: 'red',
        acquiredAtMs: 1,
        acquiredBy: _a,
      ),
      throwsArgumentError,
    );
    expect(
      () => Owned(
        kind: SkuKind.chapter,
        variantId: 'x',
        acquiredAtMs: 1,
        acquiredBy: _a,
      ),
      throwsArgumentError,
    );
    expect(
      () => Owned(kind: SkuKind.booster, acquiredAtMs: 1, acquiredBy: _a),
      throwsArgumentError,
    );
    expect(
      Owned(kind: SkuKind.chapter, acquiredAtMs: 1, acquiredBy: _a).variantId,
      isNull,
    );
  });
}
