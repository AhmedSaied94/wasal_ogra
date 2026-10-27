// A Dart model of B03's batch semantics (specs/011-m06-identity-sync
// research R23, T046), answering through `FakeApi`:
// - idempotent by id, within a batch too, and in order;
// - rejections drawn from a seed, and dependents rejected as
//   `dependency_rejected`;
// - its state from M05's own rules;
// - a `state_version` that moves only when something changed, and
//   `state_stale` whenever a batch's base isn't the version before it, as
//   B03's `process_batch` answers.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/economy/domain/economy_state.dart';
import 'package:wassal/core/economy/domain/op.dart';
import 'package:wassal/core/economy/domain/rules.dart';
import 'package:wassal/core/economy/domain/wire.dart';
import 'package:wassal/core/network/api_client.dart';
import 'package:wassal/core/sync/domain/wire/iso_time.dart';

import 'fake_api.dart';

final class ModelServer {
  ModelServer({
    required this.state,
    required this.nowMs,
    required int seed,
    this.rejectRate = 0.1,
    this.fuelMax = 5,
    this.rules = const ProductionRules(),
  }) : _random = Random(seed);

  EconomyState state;
  int stateVersion = 1;

  /// The server's clock, for `server_time`.
  final int Function() nowMs;
  final double rejectRate;
  final int fuelMax;
  final Rules rules;
  final Random _random;

  /// The operations the phone recorded, by id: the model reads their
  /// effects from M05's rules, not from the wire.
  final _known = <String, Op>{};

  /// Each answered id's result: null when accepted.
  final _results = <String, String?>{};

  /// How many times each id changed the state.
  final applied = <String, int>{};

  /// The next sync's answer is lost after the server processed it.
  bool dropNext = false;

  /// What reached the server, in order: one list per sync.
  final batches = <List<String>>[];

  void know(Op op) => _known[op.txnId.value] = op;

  void attach(FakeApi api) => api
    ..always('POST', ApiPaths.sync, FakeReply(_sync))
    ..always('GET', ApiPaths.state, FakeReply(_state));

  /// Another phone, or staff, changed the player (US3): BONAT moves and so
  /// does the version.
  void secondClientWrite(int bonat) {
    state = state.copyWith(bonat: state.bonat + bonat);
    stateVersion++;
  }

  ApiResult _sync(ApiRequest request) {
    final body = request.body! as Map<String, Object?>;
    final before = stateVersion;
    var changed = false;
    final results = <Map<String, Object?>>[];
    final ids = <String>[];
    for (final wire in body['ops']! as List<Object?>) {
      final id = (wire! as Map<String, Object?>)['client_txn_id']! as String;
      ids.add(id);
      final String? reason;
      if (_results.containsKey(id)) {
        reason = _results[id];
      } else {
        final op = _known[id] ?? fail('The phone never recorded $id.');
        reason = _decide(op);
        _results[id] = reason;
        if (reason == null) {
          state = rules.apply(state, op);
          applied[id] = (applied[id] ?? 0) + 1;
          changed = true;
        }
      }
      results.add({
        'client_txn_id': id,
        if (reason == null)
          'status': 'accepted'
        else ...{
          'status': 'rejected',
          'reason': reason,
        },
      });
    }
    batches.add(ids);
    if (changed) stateVersion++;
    if (dropNext) {
      dropNext = false;
      return const ApiUnreachable(UnreachableKind.timeout);
    }
    return apiOk({
      'state_version': stateVersion,
      'state_stale': body['base_state_version'] != before,
      'results': results,
      'wallet': _wallet(),
    });
  }

  String? _decide(Op op) {
    final refs = [op.ref?.value, op.payload['trip_start_txn']];
    for (final ref in refs) {
      if (ref is String && _results[ref] != null) return 'dependency_rejected';
    }
    if (_random.nextDouble() < rejectRate) return 'insufficient_funds';
    if (!rules.stillValid(state, op)) return 'no_trip';
    return null;
  }

  Map<String, Object?> _wallet() => {
    'jenehat': state.jenehat,
    'bonat': state.bonat,
    'fuel': state.fuel.liters,
    'fuel_max': fuelMax,
    'fuel_updated_at': msToIso(state.fuel.countedFromMs),
    'fuel_unlimited_until': switch (state.fuel.unlimitedUntilMs) {
      final until? => msToIso(until),
      null => null,
    },
  };

  ApiResult _state(ApiRequest request) => apiOk({
    'state_version': stateVersion,
    'server_time': msToIso(nowMs()),
    'player': {
      'display_name': null,
      'driver_level': 1,
      'settings': <String, Object?>{},
    },
    'wallet': _wallet(),
    'inventory': {
      for (final MapEntry(:key, :value) in state.inventory.entries)
        boosterWire[key]!: value,
    },
    'ownership': [
      for (final MapEntry(key: (kind, skuId), value: owned)
          in state.ownership.entries)
        {
          'kind': skuKindWire[kind],
          'sku_id': skuId,
          'variant': owned.variantId ?? '',
        },
    ],
    'trips': [
      for (final MapEntry(key: tripId, value: p) in state.progress.entries)
        {
          'trip_id': tripId,
          'best_stars': p.bestStars,
          'best_time_ms': ?p.bestTimeMs,
          'plays': p.plays,
        },
    ],
    'open_trip': switch (state.unfinished) {
      final open? => {
        'start_txn': open.startTxn.value,
        'trip_id': open.tripId,
        'content_version': open.contentVersion,
        'revived': open.revived,
        'traffic_jam_ads': open.trafficJamAds,
      },
      null => null,
    },
    'last_result': state.lastResult?.toJson(),
    'story': {'chapters': <Object?>[]},
    'grants': <String, Object?>{},
    'stats': <String, Object?>{},
    'comeback': {'claimable': false},
  });
}
