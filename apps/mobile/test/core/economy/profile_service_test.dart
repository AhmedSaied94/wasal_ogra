import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/economy/domain/rules.dart';
import 'package:wassal/core/economy/economy.dart';
import 'package:wassal/core/economy/economy_sync.dart';
import 'package:wassal/core/sync/domain/wire/server_wallet.dart';

import '../../helpers/economy.dart';

// The driver's name and the tutorial gift through the one service
// (specs/012-m07-onboarding/contracts/name.md, contracts/fuel-lesson.md,
// research R8), on a real database: the projection, the rollback of a
// refused name, and a server grant.

const _player = '0192f1c3-7d1e-7a4b-9c11-000000000001';

ServerWallet _wallet({int fuel = 3}) => ServerWallet(
  jenehat: 0,
  bonat: 0,
  fuel: fuel,
  fuelMax: 5,
  fuelUpdatedAtMs: testEpochMs,
);

SyncAnswer _answer(List<LedgerOp> batch, {Set<LedgerOp> rejected = const {}}) =>
    SyncAnswer(
      stateVersion: 5,
      stateStale: false,
      results: [
        for (final op in batch)
          if (rejected.contains(op))
            OpResult.rejected(op.op.txnId.value, 'validation_error')
          else
            OpResult.accepted(op.op.txnId.value),
      ],
      wallet: _wallet(),
    );

Future<LedgerOp> _name(TestEconomy e, String name) async =>
    (await e.service.setDisplayName(
      e.service.newRequestId(),
      name,
    ) as OpApplied).op;

void main() {
  group('setDisplayName', () {
    test('the view shows the name at once, offline', () async {
      final e = await testEconomy();
      expect(e.service.view.displayName, isNull);
      final outcome = await e.service.setDisplayName(
        e.service.newRequestId(),
        '  Hamada  ',
      );
      expect(outcome, isA<OpApplied>());
      expect(e.service.view.displayName, 'Hamada');
      expect((outcome as OpApplied).op.op.payload, {'display_name': 'Hamada'});
      expect(e.service.view.nameRefused, isFalse);
      expect(e.service.pendingCount, 1);
    });

    test('an invalid name is refused and stores nothing', () async {
      final e = await testEconomy();
      final outcome = await e.service.setDisplayName(
        e.service.newRequestId(),
        '1',
      );
      expect(outcome, isA<OpRefused>());
      expect((outcome as OpRefused).code, EconomyRefusal.invalidName);
      expect((await dumpTables(e.db))['ledger_ops'], isEmpty);
      expect(e.service.view.displayName, isNull);
    });

    test('the name survives a relaunch, through player_state', () async {
      var e = await testEconomy(dbFile: tempDbFile());
      await _name(e, 'Hamada');
      e = await reopen(e);
      expect(e.service.view.displayName, 'Hamada');
      await e.store.checkProjection(const ProductionRules());
    });
  });

  group('a refused name (FR-017)', () {
    test(
      'falls back to null, shown as the default, and sets nameRefused',
      () async {
        final e = await testEconomy();
        final op = await _name(e, 'Hamada');
        await e.service.applyAnswer(
          _answer([op], rejected: {op}),
          batch: [op],
          playerId: _player,
        );
        expect(e.service.view.displayName, isNull);
        expect(e.service.view.nameRefused, isTrue);
      },
    );

    test('falls back to the last accepted name', () async {
      final e = await testEconomy();
      final first = await _name(e, 'Hamada');
      await e.service.applyAnswer(
        _answer([first]),
        batch: [first],
        playerId: _player,
      );
      expect(e.service.view.displayName, 'Hamada');
      final second = await _name(e, 'Sayed');
      expect(e.service.view.displayName, 'Sayed');
      await e.service.applyAnswer(
        _answer([second], rejected: {second}),
        batch: [second],
        playerId: _player,
      );
      expect(e.service.view.displayName, 'Hamada');
      expect(e.service.view.nameRefused, isTrue);
    });

    test('a new name clears nameRefused', () async {
      final e = await testEconomy();
      final op = await _name(e, 'Hamada');
      await e.service.applyAnswer(
        _answer([op], rejected: {op}),
        batch: [op],
        playerId: _player,
      );
      expect(e.service.view.nameRefused, isTrue);
      await _name(e, 'Sayed');
      expect(e.service.view.nameRefused, isFalse);
      expect(e.service.view.displayName, 'Sayed');
    });

    test('nameRefused is read again at launch', () async {
      var e = await testEconomy(dbFile: tempDbFile());
      final op = await _name(e, 'Hamada');
      await e.service.applyAnswer(
        _answer([op], rejected: {op}),
        batch: [op],
        playerId: _player,
      );
      e = await reopen(e);
      expect(e.service.view.nameRefused, isTrue);
    });

    test('a name dropped by another account isn\'t a refusal', () async {
      final e = await testEconomy();
      await _name(e, 'Hamada');
      await e.service.adoptAccount(
        EconomyState.newPlayer(fuelMax: 5, nowMs: testEpochMs),
        playerId: _player,
        stateVersion: 3,
      );
      expect(e.service.view.nameRefused, isFalse);
    });
  });

  group('grantTutorialGift', () {
    test('fills the tank, then refuses already_granted', () async {
      final e = await testEconomy(
        firstState: (nowMs) => EconomyState(
          jenehat: 0,
          bonat: 0,
          fuel: FuelState(liters: 1, countedFromMs: nowMs),
        ),
      );
      final first = await e.service.grantTutorialGift(e.service.newRequestId());
      expect(first, isA<OpApplied>());
      expect((first as OpApplied).op.op.fuelDelta, 4);
      expect(e.service.view.fuel.liters, 5);
      expect(e.service.view.tutorialGranted, isTrue);

      final second = await e.service.grantTutorialGift(
        e.service.newRequestId(),
      );
      expect(second, isA<OpRefused>());
      expect((second as OpRefused).code, EconomyRefusal.alreadyGranted);
      final rows = (await dumpTables(e.db))['ledger_ops']!;
      expect(rows.where((r) => r['op_type'] == 'tutorial_gift'), hasLength(1));
    });

    test('a server grant drops a pending local one', () async {
      final e = await testEconomy(
        firstState: (nowMs) => EconomyState(
          jenehat: 0,
          bonat: 0,
          fuel: FuelState(liters: 1, countedFromMs: nowMs),
        ),
      );
      await e.service.grantTutorialGift(e.service.newRequestId());
      expect(e.service.view.fuel.liters, 5);

      await e.service.replaceFromServer(
        EconomyState(
          jenehat: 0,
          bonat: 0,
          fuel: const FuelState(liters: 2, countedFromMs: testEpochMs),
          tutorialGranted: true,
        ),
        playerId: _player,
        stateVersion: 9,
      );
      expect(e.service.view.tutorialGranted, isTrue);
      expect(
        e.service.view.fuel.liters,
        2,
        reason: 'the pending gift no longer applies',
      );
      await e.store.checkProjection(const ProductionRules());
    });

    test('the grant survives a relaunch', () async {
      var e = await testEconomy(dbFile: tempDbFile());
      await e.service.grantTutorialGift(e.service.newRequestId());
      e = await reopen(e);
      expect(e.service.view.tutorialGranted, isTrue);
    });
  });
}
