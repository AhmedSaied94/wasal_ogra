import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/sync/domain/wire/bootstrap.dart';
import 'package:wassal/core/sync/domain/wire/iso_time.dart';
import 'package:wassal/core/sync/domain/wire/link.dart';
import 'package:wassal/core/sync/domain/wire/reader.dart';
import 'package:wassal/core/sync/domain/wire/server_wallet.dart';
import 'package:wassal/core/sync/domain/wire/state.dart';
import 'package:wassal/core/sync/domain/wire/sync_answer.dart';
import 'package:wassal/core/sync/domain/wire/token_pair.dart';

// The strict readers of the server's answers (specs/011-m06-identity-sync,
// contracts/api-client.md "Readers", B02 and B03's contracts): integers
// only where an integer is expected, unknown fields ignored.

const _player = '0192f1c3-7d1e-7a4b-9c11-000000000001';
const _start = '0192f3a1-7b2c-7d4e-8f00-000000000001';

final _nine = DateTime.utc(2026, 10, 17, 9).millisecondsSinceEpoch;

Map<String, Object?> _wallet() => {
  'jenehat': 1240,
  'bonat': 35,
  'fuel': 3,
  'fuel_max': 5,
  'fuel_updated_at': '2026-10-17T08:41:00Z',
  'fuel_unlimited_until': null,
};

Map<String, Object?> _bootstrap() => {
  'server_time': '2026-10-17T09:00:00Z',
  'player': {
    'player_id': _player,
    'display_name': 'name',
    'driver_level': 4,
    'country': 'EG',
    'providers': ['google'],
  },
  'wallet': _wallet(),
  'entitlements': {
    'remove_ads': false,
    'subscription': null,
    'season_passes': <Object?>[],
    'flags': {'no_interstitials': false, 'fuel_max_bonus': 0},
  },
  'state_version': 42,
  'content': {'version': 7, 'manifest_url': '/v1/content/manifest'},
  'client': {
    'min_version': '1.0.0',
    'latest_version': '1.2.0',
    'force_update': false,
  },
  'daily': {
    'game_date': '2026-10-17',
    'challenge_available': false,
    'reward_claimable': false,
  },
  'comeback': {'claimable': true},
};

Map<String, Object?> _state({bool open = true, bool last = true}) => {
  'state_version': 42,
  'server_time': '2026-10-17T09:00:00.250Z',
  'player': {
    'display_name': 'name',
    'driver_level': 4,
    'settings': {'digits': 'arabic'},
  },
  'wallet': _wallet(),
  'inventory': {'change_bag': 2, 'wake_all': 0, 'ledger_peek': 1},
  'ownership': [
    {'kind': 'vehicle', 'sku_id': 'micro_old', 'variant': ''},
    {'kind': 'item', 'sku_id': 'salon.nish', 'variant': 'classic'},
  ],
  'trips': [
    {
      'trip_id': 'line_hay.01',
      'best_stars': 3,
      'best_time_ms': 91200,
      'plays': 4,
    },
    {'trip_id': 'line_hay.02', 'best_stars': 0, 'plays': 1},
  ],
  'open_trip': open
      ? {
          'start_txn': _start,
          'trip_id': 'line_hay.05',
          'content_version': 7,
          'revived': false,
          'traffic_jam_ads': 0,
        }
      : null,
  'last_result': last
      ? {
          'start_txn': _start,
          'outcome': 'finished',
          'earnings_jenehat': 46,
          'doubled': false,
        }
      : null,
  'story': {
    'chapters': [
      {'chapter_id': 'ch1_first_job', 'status': 'open'},
    ],
  },
  'grants': {'tutorial': true},
  'stats': {'trips_played': 31},
  'comeback': {'claimable': false},
};

Map<String, Object?> _answer() => {
  'state_version': 43,
  'state_stale': false,
  'results': [
    {'client_txn_id': 'a', 'status': 'accepted'},
    {
      'client_txn_id': 'b',
      'status': 'accepted',
      'granted': [
        {'kind': 'booster', 'id': 'change_bag', 'count': 1},
      ],
    },
    {
      'client_txn_id': 'c',
      'status': 'rejected',
      'reason': 'insufficient_funds',
    },
    {
      'client_txn_id': 'd',
      'status': 'rejected',
      'reason': 'a_reason_from_later',
      'details': {'field': 'trip_id'},
    },
  ],
  'wallet': _wallet(),
};

Map<String, Object?> _copy(Map<String, Object?> json) =>
    (jsonDecode(jsonEncode(json)) as Map<String, Object?>);

/// Changes one value of a copy of [json] at [path] (keys and list indexes).
Map<String, Object?> _with(
  Map<String, Object?> json,
  List<Object> path,
  Object? value,
) {
  final copy = _copy(json);
  Object? node = copy;
  for (final key in path.take(path.length - 1)) {
    node = switch ((node, key)) {
      (final Map<String, Object?> map, final String k) => map[k],
      (final List<Object?> list, final int i) => list[i],
      _ => throw StateError('bad path $path'),
    };
  }
  switch ((node, path.last)) {
    case (final Map<String, Object?> map, final String k):
      map[k] = value;
    case (final List<Object?> list, final int i):
      list[i] = value;
    default:
      throw StateError('bad path $path');
  }
  return copy;
}

final _wire = throwsA(isA<WireFormatException>());

/// [read] refuses a float, a boolean and a string at each integer [paths].
void _strictIntegers(
  Map<String, Object?> json,
  Object? Function(Object? json) read,
  List<List<Object>> paths,
) {
  for (final path in paths) {
    for (final bad in <Object>[1.5, 2.0, true, '7']) {
      expect(() => read(_with(json, path, bad)), _wire, reason: '$path = $bad');
    }
  }
}

void main() {
  group('times', () {
    test('read UTC with and without milliseconds', () {
      expect(isoToMs('2026-10-17T09:00:00Z'), _nine);
      expect(isoToMs('2026-10-17T09:00:00.250Z'), _nine + 250);
      expect(isoToMs('2026-10-17T09:00:00.250123Z'), _nine + 250);
      expect(msToIso(_nine + 250), '2026-10-17T09:00:00.250Z');
    });

    test('refuse a time that is not UTC, or not a time', () {
      for (final text in [
        '2026-10-17T09:00:00',
        '2026-10-17T09:00:00+02:00',
        '2026-10-17 09:00:00Z',
        '1792627200000',
        '',
      ]) {
        expect(() => isoToMs(text), _wire, reason: text);
      }
    });
  });

  group('TokenPair', () {
    test('reads with and without created', () {
      final created = TokenPair.fromJson({
        'player_id': _player,
        'access': 'a',
        'refresh': 'r',
        'access_expires_in': 900,
        'providers': <Object?>[],
        'created': true,
        'refresh_expires_in': 1,
      });
      expect(created.playerId, _player);
      expect(created.accessExpiresIn, 900);
      expect(created.providers, isEmpty);
      expect(created.created, isTrue);
      expect(created.toString(), 'TokenPair($_player)');

      final refreshed = TokenPair.fromJson({
        'player_id': _player,
        'access': 'a2',
        'refresh': 'r2',
        'access_expires_in': 900,
        'providers': ['google'],
      });
      expect(refreshed.created, isNull);
      expect(refreshed.providers, ['google']);
    });

    test('refuses a bad expiry, a missing token and a bad provider', () {
      final json = {
        'player_id': _player,
        'access': 'a',
        'refresh': 'r',
        'access_expires_in': 900,
        'providers': <Object?>[],
      };
      _strictIntegers(json, TokenPair.fromJson, [
        ['access_expires_in'],
      ]);
      expect(() => TokenPair.fromJson(_with(json, ['refresh'], null)), _wire);
      expect(() => TokenPair.fromJson(_with(json, ['providers'], [1])), _wire);
      expect(() => TokenPair.fromJson([json]), _wire);
    });

    test('tells a token answer from a link answer', () {
      expect(TokenPair.isTokenPair({'access': 'a', 'refresh': 'r'}), isTrue);
      expect(
        TokenPair.isTokenPair({'player_id': _player, 'providers': <Object?>[]}),
        isFalse,
      );
    });
  });

  group('ServerWallet', () {
    test('reads times with and without milliseconds, and null unlimited', () {
      final wallet = ServerWallet.fromJson(_wallet());
      expect(wallet.jenehat, 1240);
      expect(wallet.bonat, 35);
      expect(wallet.fuel, 3);
      expect(wallet.fuelMax, 5);
      expect(wallet.fuelUpdatedAtMs, _nine - 19 * 60000);
      expect(wallet.fuelUnlimitedUntilMs, isNull);
      expect(wallet.fuelState.liters, 3);
      expect(wallet.fuelState.countedFromMs, _nine - 19 * 60000);

      final unlimited = ServerWallet.fromJson(
        _with(
          _with(_wallet(), ['fuel_unlimited_until'], '2026-10-17T10:00:00.5Z'),
          ['fuel_updated_at'],
          '2026-10-17T08:41:00.125Z',
        ),
      );
      expect(unlimited.fuelUnlimitedUntilMs, _nine + 3600000 + 500);
      expect(unlimited.fuelUpdatedAtMs, _nine - 19 * 60000 + 125);
      expect(unlimited.fuelState.unlimitedUntilMs, _nine + 3600000 + 500);
    });

    test('refuses non-integer amounts', () {
      _strictIntegers(_wallet(), ServerWallet.fromJson, [
        ['jenehat'],
        ['bonat'],
        ['fuel'],
        ['fuel_max'],
      ]);
      expect(
        () => ServerWallet.fromJson(_with(_wallet(), ['fuel_updated_at'], 1)),
        _wire,
      );
    });
  });

  group('BootstrapSnapshot', () {
    test('reads every block, with the neutral ones', () {
      final snapshot = BootstrapSnapshot.fromJson(_bootstrap());
      expect(snapshot.serverTimeMs, _nine);
      expect(snapshot.player.playerId, _player);
      expect(snapshot.player.providers, ['google']);
      expect(snapshot.player.displayName, 'name');
      expect(snapshot.player.driverLevel, 4);
      expect(snapshot.wallet.jenehat, 1240);
      expect(snapshot.stateVersion, 42);
      expect(snapshot.contentVersion, 7);
      expect(snapshot.client.minVersion, '1.0.0');
      expect(snapshot.client.latestVersion, '1.2.0');
      expect(snapshot.client.forceUpdate, isFalse);
      expect(snapshot.daily.gameDate, '2026-10-17');
      expect(snapshot.daily.challengeAvailable, isFalse);
      expect(snapshot.comebackClaimable, isTrue);
      final e = snapshot.entitlements;
      expect(e.removeAds, isFalse);
      expect(e.subscriptionUntilMs, isNull);
      expect(e.seasonPasses, isEmpty);
      expect(e.noInterstitials, isFalse);
      expect(e.fuelMaxBonus, 0);
      expect(snapshot.raw, _bootstrap());
    });

    // B03 sends "" for a name never given (M07: the re-ask and «الأسطى»).
    test('reads a blank name as none', () {
      final json = _with(_bootstrap(), ['player', 'display_name'], '');
      expect(BootstrapSnapshot.fromJson(json).player.displayName, isNull);
    });

    test('takes a null content version, no name and no level', () {
      var json = _with(_bootstrap(), ['content', 'version'], null);
      json = _with(json, ['player', 'display_name'], null);
      json = _with(json, ['player', 'driver_level'], null);
      final snapshot = BootstrapSnapshot.fromJson(json);
      expect(snapshot.contentVersion, isNull);
      expect(snapshot.player.displayName, isNull);
      expect(snapshot.player.driverLevel, isNull);
    });

    test('reads a subscription and flags missing', () {
      final json = _with(
        _with(
          _bootstrap(),
          ['entitlements', 'subscription'],
          {'until': '2026-11-17T09:00:00Z', 'product_id': 'x'},
        ),
        ['entitlements', 'flags'],
        null,
      );
      final e = BootstrapSnapshot.fromJson(json).entitlements;
      expect(
        e.subscriptionUntilMs,
        DateTime.utc(2026, 11, 17, 9).millisecondsSinceEpoch,
      );
      expect(e.noInterstitials, isFalse);
      expect(e.fuelMaxBonus, 0);
    });

    test('refuses non-integers and a missing block', () {
      _strictIntegers(_bootstrap(), BootstrapSnapshot.fromJson, [
        ['state_version'],
        ['content', 'version'],
        ['wallet', 'bonat'],
        ['player', 'driver_level'],
        ['entitlements', 'flags', 'fuel_max_bonus'],
      ]);
      for (final block in ['player', 'wallet', 'client', 'daily', 'comeback']) {
        expect(
          () => BootstrapSnapshot.fromJson(_with(_bootstrap(), [block], null)),
          _wire,
          reason: block,
        );
      }
      expect(
        () => BootstrapSnapshot.fromJson(
          _with(_bootstrap(), ['client', 'force_update'], 'yes'),
        ),
        _wire,
      );
    });
  });

  group('StateSnapshot', () {
    test('reads the state with an open trip and a last result', () {
      final state = StateSnapshot.fromJson(_state());
      expect(state.stateVersion, 42);
      expect(state.serverTimeMs, _nine + 250);
      expect(state.displayName, 'name');
      expect(state.driverLevel, 4);
      expect(state.wallet.fuel, 3);
      expect(state.inventory, {
        'change_bag': 2,
        'wake_all': 0,
        'ledger_peek': 1,
      });
      expect(
        [for (final o in state.ownership) (o.kind, o.skuId, o.variant)],
        [('vehicle', 'micro_old', ''), ('item', 'salon.nish', 'classic')],
      );
      expect(
        [
          for (final t in state.trips)
            (t.tripId, t.bestStars, t.bestTimeMs, t.plays),
        ],
        [('line_hay.01', 3, 91200, 4), ('line_hay.02', 0, null, 1)],
      );
      final open = state.openTrip!;
      expect(open.startTxn, _start);
      expect(open.tripId, 'line_hay.05');
      expect(open.contentVersion, 7);
      expect(open.revived, isFalse);
      expect(open.trafficJamAds, 0);
      expect(state.lastResult!.json, {
        'start_txn': _start,
        'outcome': 'finished',
        'earnings_jenehat': 46,
        'doubled': false,
      });
    });

    test('keeps story, grants and stats raw', () {
      final state = StateSnapshot.fromJson(_state());
      expect(state.raw['story'], _state()['story']);
      expect(state.raw['grants'], {'tutorial': true});
      expect(state.raw['stats'], {'trips_played': 31});
    });

    test('reads a blank name as none', () {
      final json = _with(_state(), ['player', 'display_name'], '');
      expect(StateSnapshot.fromJson(json).displayName, isNull);
    });

    test('reads null open_trip and last_result', () {
      final state = StateSnapshot.fromJson(_state(open: false, last: false));
      expect(state.openTrip, isNull);
      expect(state.lastResult, isNull);
    });

    test('reads an ownership row with no variant as an empty one', () {
      final json = _copy(_state());
      ((json['ownership']! as List<Object?>).first! as Map<String, Object?>)
          .remove('variant');
      expect(StateSnapshot.fromJson(json).ownership.first.variant, '');
    });

    test('refuses non-integers wherever an integer is expected', () {
      _strictIntegers(_state(), StateSnapshot.fromJson, [
        ['state_version'],
        ['inventory', 'change_bag'],
        ['trips', 0, 'best_stars'],
        ['trips', 0, 'best_time_ms'],
        ['trips', 0, 'plays'],
        ['open_trip', 'content_version'],
        ['open_trip', 'traffic_jam_ads'],
        ['last_result', 'earnings_jenehat'],
        ['wallet', 'fuel_max'],
        ['player', 'driver_level'],
      ]);
      expect(
        () => StateSnapshot.fromJson(
          _with(_state(), ['open_trip', 'revived'], 0),
        ),
        _wire,
      );
      expect(
        () => StateSnapshot.fromJson(_with(_state(), ['ownership'], {})),
        _wire,
      );
    });
  });

  group('SyncAnswer', () {
    test('reads accepted, granted, rejected and an unknown reason', () {
      final answer = SyncAnswer.fromJson(_answer());
      expect(answer.stateVersion, 43);
      expect(answer.stateStale, isFalse);
      expect(answer.wallet.jenehat, 1240);
      final [a, b, c, d] = answer.results;
      expect(
        (a.txnId, a.accepted, a.granted, a.reason),
        ('a', true, null, null),
      );
      expect(b.accepted, isTrue);
      expect(b.granted, [
        {'kind': 'booster', 'id': 'change_bag', 'count': 1},
      ]);
      expect((c.accepted, c.reason), (false, 'insufficient_funds'));
      // A reason the app doesn't know is kept, for the generic rejection.
      expect((d.accepted, d.reason), (false, 'a_reason_from_later'));
    });

    test('reads state_stale, and a rejection without a reason', () {
      final json = _with(_answer(), ['state_stale'], true);
      ((json['results']! as List<Object?>)[2]! as Map<String, Object?>).remove(
        'reason',
      );
      final answer = SyncAnswer.fromJson(json);
      expect(answer.stateStale, isTrue);
      expect(answer.results[2].reason, 'unknown');
    });

    test('refuses non-integers, a bad status and a bad flag', () {
      _strictIntegers(_answer(), SyncAnswer.fromJson, [
        ['state_version'],
        ['wallet', 'jenehat'],
      ]);
      expect(
        () => SyncAnswer.fromJson(
          _with(_answer(), ['results', 0, 'status'], 'maybe'),
        ),
        _wire,
      );
      expect(
        () => SyncAnswer.fromJson(_with(_answer(), ['state_stale'], 0)),
        _wire,
      );
    });
  });

  group('link', () {
    final details = {
      'current': {'driver_level': 2, 'chapter_id': 'ch1_first_job', 'bonat': 5},
      'existing': {
        'player_id': _player,
        'driver_level': 7,
        'chapter_id': 'ch2_wedding',
        'bonat': 40,
        'country': 'EG',
      },
    };

    test('reads the link answer', () {
      final result = LinkResult.fromJson({
        'player_id': _player,
        'providers': ['google'],
      });
      expect(result.playerId, _player);
      expect(result.providers, ['google']);
    });

    test('reads the provider_in_use details', () {
      final (:current, :existing) = conflictOf(details);
      expect(
        (
          current.driverLevel,
          current.chapterId,
          current.bonat,
          current.playerId,
        ),
        (2, 'ch1_first_job', 5, null),
      );
      expect(
        (existing.driverLevel, existing.chapterId, existing.bonat),
        (7, 'ch2_wedding', 40),
      );
      expect(existing.playerId, _player);
    });

    test('refuses details without the existing player, or with floats', () {
      expect(
        () => conflictOf(_with(details, ['existing', 'player_id'], null)),
        _wire,
      );
      _strictIntegers(
        details,
        (json) => conflictOf(json! as Map<String, Object?>),
        [
          ['current', 'bonat'],
          ['existing', 'driver_level'],
        ],
      );
    });
  });
}
