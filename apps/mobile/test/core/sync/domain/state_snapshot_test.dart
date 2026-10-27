import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/economy/domain/economy_state.dart';
import 'package:wassal/core/economy/domain/txn_id.dart';
import 'package:wassal/core/sync/domain/state_snapshot.dart';
import 'package:wassal/core/sync/domain/wire/iso_time.dart';
import 'package:wassal/core/sync/domain/wire/state.dart';

import '../../../helpers/economy.dart';
import '../../../helpers/sync.dart';

// The server's full state as the economy's (specs/011-m06-identity-sync,
// contracts/sync.md "Taking the full state", research R12).

const _start = '0192f3a1-7b2c-7d4e-8f00-000000000042';

Map<String, Object?> _json({Map<String, Object?>? openTrip}) => {
  ...stateJson(),
  'inventory': {
    'change_bag': 2,
    'wake_all': 0,
    'ledger_peek': 1,
    'traffic_jam': 3,
    'revive': 4,
  },
  'ownership': [
    {'kind': 'vehicle', 'sku_id': 'micro_old', 'variant': ''},
    {'kind': 'item', 'sku_id': 'salon.nish', 'variant': 'classic'},
    {'kind': 'item', 'sku_id': 'salon.gone', 'variant': 'plain'},
    {'kind': 'chapter', 'sku_id': 'ch3_shabka', 'variant': ''},
    {'kind': 'booster', 'sku_id': 'change_bag', 'variant': ''},
    {'kind': 'season_pass', 'sku_id': 's1', 'variant': ''},
    {'kind': 'item', 'sku_id': 'salon.sitara', 'variant': ''},
    {'kind': 'vehicle', 'sku_id': 'micro_new', 'variant': 'red'},
  ],
  'trips': [
    {
      'trip_id': 'line_hay.01',
      'best_stars': 3,
      'best_time_ms': 91200,
      'plays': 4,
    },
    {'trip_id': 'line_gone.09', 'best_stars': 0, 'plays': 1},
  ],
  'open_trip': openTrip,
  'last_result': {
    'start_txn': _start,
    'outcome': 'finished',
    'earnings_jenehat': 46,
    'doubled': true,
  },
  'story': {
    'chapters': [
      {'chapter_id': 'ch1_first_job', 'status': 'complete'},
    ],
  },
  'grants': {'tutorial': true},
  'stats': {'trips_played': 99},
};

const _open = {
  'start_txn': _start,
  'trip_id': 'line_hay.01',
  'content_version': 7,
  'revived': true,
  'traffic_jam_ads': 1,
};

EconomyState _map(
  Map<String, Object?> json, {
  bool Function(TxnId start)? hasTripRecord,
}) => stateFromSnapshot(
  StateSnapshot.fromJson(json),
  hasTripRecord: hasTripRecord ?? (_) => true,
  content: sampleContent(),
);

void main() {
  final serverTimeMs = isoToMs('2026-10-17T09:00:00.250Z');

  test('the wallet: balances and the tank', () {
    final state = _map(_json());
    expect(state.jenehat, 900);
    expect(state.bonat, 77);
    expect(
      state.fuel,
      FuelState(liters: 3, countedFromMs: isoToMs('2026-10-17T09:00:00Z')),
    );
  });

  test('the in-trip boosters, without zero counts or other kinds', () {
    expect(_map(_json()).inventory, {
      BoosterId.changeBag: 2,
      BoosterId.ledgerPeek: 1,
      BoosterId.trafficJam: 3,
    });
  });

  test('ownership: "" is no variant, items keep theirs, at server_time, by '
      'no operation', () {
    final ownership = _map(_json()).ownership;
    expect(ownership[(SkuKind.vehicle, 'micro_old')]?.variantId, isNull);
    expect(ownership[(SkuKind.item, 'salon.nish')]?.variantId, 'classic');
    for (final owned in ownership.values) {
      expect(owned.acquiredAtMs, serverTimeMs);
      expect(owned.acquiredBy, isNull);
    }
  });

  test('ids the pack lacks are kept', () {
    final state = _map(_json());
    expect(state.ownership.keys, contains((SkuKind.item, 'salon.gone')));
    expect(state.progress.keys, contains('line_gone.09'));
  });

  test('what the economy can\'t own is skipped, and only an item has a '
      'variant', () {
    final keys = _map(_json()).ownership.keys.toSet();
    expect(keys, {
      (SkuKind.vehicle, 'micro_old'),
      (SkuKind.item, 'salon.nish'),
      (SkuKind.item, 'salon.gone'),
      (SkuKind.chapter, 'ch3_shabka'),
    });
  });

  test('trip progress, with no first completion time', () {
    final progress = _map(_json()).progress;
    expect(
      progress['line_hay.01'],
      const TripProgress(bestStars: 3, bestTimeMs: 91200, plays: 4),
    );
    expect(progress['line_hay.01']!.firstCompletedAtMs, isNull);
    expect(progress['line_gone.09']!.bestTimeMs, isNull);
  });

  test('the open trip, when this phone has its record', () {
    final state = _map(_json(openTrip: _open));
    final open = state.unfinished!;
    expect(open.startTxn.value, _start);
    expect(open.tripId, 'line_hay.01');
    expect(open.contentVersion, 7);
    expect(open.maxEarningsJenehat, 20, reason: 'the sample pack\'s');
    expect(open.startedAtMs, serverTimeMs);
    expect(open.revived, isTrue);
    expect(open.trafficJamAds, 1);
  });

  test('the open trip is left out without its record, or its trip', () {
    expect(
      _map(_json(openTrip: _open), hasTripRecord: (_) => false).unfinished,
      isNull,
    );
    expect(
      _map(_json(openTrip: {..._open, 'trip_id': 'line_gone.09'})).unfinished,
      isNull,
    );
    expect(
      _map(_json(openTrip: {..._open, 'start_txn': 'not-a-uuid'})).unfinished,
      isNull,
    );
  });

  test('the last result', () {
    final last = _map(_json()).lastResult!;
    expect(last.startTxn.value, _start);
    expect(last.earningsJenehat, 46);
    expect(last.doubled, isTrue);
  });

  test('story, grants and stats change nothing', () {
    final bare = {..._json()}
      ..['story'] = {'chapters': <Object?>[]}
      ..['grants'] = <String, Object?>{}
      ..['stats'] = <String, Object?>{};
    expect(_map(_json()).toJson(), _map(bare).toJson());
  });
}
