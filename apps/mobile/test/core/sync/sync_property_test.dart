import 'dart:math';

import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/economy/domain/rules.dart';
import 'package:wassal/core/economy/economy.dart';
import 'package:wassal/core/economy/economy_service.dart';
import 'package:wassal/core/sync/state_applier.dart';
import 'package:wassal/core/sync/sync_engine.dart';
import 'package:wassal/features/trip/data/trip_records.dart';

import '../../helpers/economy.dart';
import '../../helpers/fake_api.dart';
import '../../helpers/model_server.dart';
import '../../helpers/sync.dart';

// SC-003 (specs/011-m06-identity-sync research R23, T046): seeded
// sequences of recorded operations, lost answers, retries, kills before an
// answer is applied, and second-client writes, against ModelServer. After
// the queue drains, the phone's balances, tank, boosters, ownership and
// trip progress equal the model's, and the model applied no id twice.
//
// Seeds 0–999 (T053). A failure names its seed; rerun one with
// `--plain-name 'seed N'` after narrowing `_seeds`.

final _seeds = [for (var seed = 0; seed < 1000; seed++) seed];

/// This phone recorded every trip it started.
final class _AllRecords implements TripRecords {
  @override
  Future<bool> has(TxnId start) async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Phone {
  _Phone(this.economy, this.server, this.api, int seed)
    : _random = Random(seed) {
    engine = _engine();
  }

  final TestEconomy economy;
  final ModelServer server;
  final FakeApi api;
  final Random _random;
  final time = FakeSyncTime();
  late SyncRunner engine;

  EconomyService get service => economy.service;

  SyncRunner _engine() => SyncRunner(
    account: FakeSyncAccount(),
    api: PlainAuthorizedApi(api),
    economy: service,
    states: ServerStateApplier(
      economy: service,
      trips: _AllRecords(),
      content: () => economy.content,
      writeProfile: ({displayName, driverLevel}) async {},
    ),
    time: time,
    serverStateVersion: () => server.stateVersion,
    random: _random,
  );

  T _pick<T>(List<T> from) => from[_random.nextInt(from.length)];

  /// One thing the player does; the economy may refuse it.
  Future<void> play() async {
    final id = service.newRequestId();
    final OpOutcome outcome;
    if (service.state.unfinished case final open?) {
      outcome = switch (_random.nextInt(5)) {
        0 => await service.useBooster(
          id,
          booster: _pick(inTripBoosters.toList()),
        ),
        1 => await service.applyAdReward(
          id,
          placement: _pick([AdPlacement.tripRevive, AdPlacement.trafficJam]),
        ),
        _ => await service.recordResult(
          id,
          start: open.startTxn,
          result: tripResult(
            tripId: open.tripId,
            stars: 1 + _random.nextInt(3),
            earnings: _random.nextInt(16),
            durationMs: 60000 + _random.nextInt(60000),
          ),
        ),
      };
    } else {
      outcome = switch (_random.nextInt(6)) {
        0 || 1 => await service.startTrip(
          id,
          tripId: _pick(['line_hay.01', 'line_hay.02', 'line_hay.03']),
        ),
        2 => await service.buy(
          id,
          kind: SkuKind.booster,
          skuId: _pick(['change_bag', 'wake_all', 'ledger_peek']),
        ),
        3 => await service.buy(
          id,
          kind: SkuKind.item,
          skuId: 'salon.nish',
          variantId: _pick(['classic', 'crystal', 'modern']),
        ),
        _ => await service.applyAdReward(
          id,
          placement: _pick([AdPlacement.resultDouble, AdPlacement.fuelRefill]),
        ),
      };
    }
    if (outcome case OpApplied(:final op, repeated: false)) {
      server.know(op.op);
    }
  }

  /// What the network and the server do between two moves.
  Future<void> weather() async {
    final roll = _random.nextDouble();
    if (roll < 0.3) {
      // A pass, its first answer sometimes lost.
      server.dropNext = _random.nextDouble() < 0.2;
      await engine.syncNow();
    } else if (roll < 0.36) {
      // The app dies after the server answered and before the phone applied
      // it: the engine's memory is gone, the database's rows aren't.
      server.dropNext = true;
      await engine.syncNow();
      engine.dispose();
      engine = _engine();
    } else if (roll < 0.42) {
      server.secondClientWrite(1 + _random.nextInt(40));
    }
    server.dropNext = false;
    economy.passTime(Duration(minutes: _random.nextInt(25)));
  }

  /// Passes until nothing is pending and the base is the server's.
  Future<void> drain() async {
    for (var round = 0; round < 40; round++) {
      await engine.syncNow();
      if (service.pendingCount == 0 &&
          service.baseInfo.stateVersion == server.stateVersion) {
        return;
      }
    }
    fail('The queue never drained: ${engine.snapshot.lastOutcome}.');
  }
}

Map<BoosterId, int> _boosters(EconomyState s) => {
  for (final MapEntry(:key, :value) in s.inventory.entries)
    if (value > 0) key: value,
};

Map<String, (int, int?, int)> _progress(EconomyState s) => {
  for (final MapEntry(:key, value: p) in s.progress.entries)
    key: (p.bestStars, p.bestTimeMs, p.plays),
};

Future<void> _sequence(int seed) async {
  final economy = await testEconomy(
    firstState: (nowMs) => EconomyState.newPlayer(
      fuelMax: 5,
      nowMs: nowMs,
    ).copyWith(jenehat: 2000, bonat: 200),
  );
  final server = ModelServer(
    state: economy.service.state,
    nowMs: economy.clock.nowMs,
    seed: seed,
    rejectRate: 0.12,
  );
  final api = FakeApi(elapsedMs: () => economy.uptime.elapsedRealtimeMs);
  server.attach(api);
  final phone = _Phone(economy, server, api, seed);
  addTearDown(() => phone.engine.dispose());

  final moves = 5 + Random(seed).nextInt(26);
  for (var move = 0; move < moves; move++) {
    await phone.play();
    await phone.weather();
  }
  await phone.drain();

  final device = economy.service.state;
  final model = server.state;
  expect(device.jenehat, model.jenehat, reason: 'JENEHAT');
  expect(device.bonat, model.bonat, reason: 'BONAT');
  expect(device.fuel, model.fuel, reason: 'fuel');
  expect(_boosters(device), _boosters(model), reason: 'boosters');
  expect(device.ownership.keys.toSet(), model.ownership.keys.toSet());
  expect(_progress(device), _progress(model), reason: 'trip progress');
  expect(
    server.applied.entries.where((e) => e.value != 1),
    isEmpty,
    reason: 'an id applied twice',
  );
  await economy.store.checkProjection(const ProductionRules());
}

void main() {
  for (final seed in _seeds) {
    test('seed $seed', () => _sequence(seed));
  }
}
