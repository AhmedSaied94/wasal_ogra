@Tags(['backend'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show Locale;
import 'package:wassal/core/economy/economy.dart';
import 'package:wassal/core/network/api_client.dart';
import 'package:wassal/core/sync/domain/op_wire.dart';
import 'package:wassal/core/sync/domain/wire/state.dart';
import 'package:wassal/core/sync/sync_events.dart';
import 'package:wassal/features/onboarding/domain/name_suggestions.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

import 'e2e.dart';

// The first session's two operations against the dev stack (specs/012-
// m07-onboarding, T072, T085): the driver's name and the tutorial gift
// reach the server and come back in its state; the server holds one gift,
// and a second is `already_granted`; a name its filter holds comes back
// refused, and the phone asks again.

/// The term `seed_backend.py` puts in the server's name filter: a name the
/// phone's own rules let through.
const _filtered = 'ممنوع';

/// The first name the Name card suggests: the server's filter passes every
/// pooled name (backend test_name_pool.py).
final _name = namePoolOf(lookupAppLocalizations(const Locale('ar')).namePool)
    .first;

Future<StateSnapshot> _state(E2eDevice device) async {
  final answer = await device.account.authorized.send(
    const ApiRequest.get(ApiPaths.state, receiveTimeout: readReceiveTimeout),
  );
  return StateSnapshot.fromJson((answer as ApiOk).json);
}

/// A phone online, with the name and the gift recorded and synced; the
/// gift's operation as it was sent.
Future<(E2eDevice, Map<String, Object?>)> _synced() async {
  final device = await e2eDevice();
  final engine = e2eEngine(device);
  final economy = device.economy.service;
  expect(await device.account.ensureSession(), isTrue);

  expect(
    await economy.setDisplayName(economy.newRequestId(), _name),
    isA<OpApplied>(),
  );
  expect(
    await economy.grantTutorialGift(economy.newRequestId()),
    isA<OpApplied>(),
  );
  final gift = (await economy.pendingOps()).singleWhere(
    (row) => row.op.type == OpType.tutorialGift,
  );
  await engine.syncNow();
  expect(economy.pendingCount, 0, reason: '${engine.snapshot.lastError}');
  return (device, opWire(gift));
}

void main() {
  setUpAll(useRealHttp);

  test('the name and the gift come back in the state', () async {
    final (device, _) = await _synced();
    final state = await _state(device);
    expect(state.displayName, _name);
    expect(state.grants.tutorial, isTrue);
    expect(device.economy.service.view.tutorialGranted, isTrue);
  });

  test('a second tutorial gift is already granted', () async {
    final (device, gift) = await _synced();
    final before = await _state(device);
    final again = {
      ...gift,
      'client_txn_id': device.economy.service.newRequestId().value,
    };
    final answer = await device.account.authorized.send(
      ApiRequest.post(
        ApiPaths.sync,
        receiveTimeout: syncReceiveTimeout,
        body: {
          'base_state_version': before.stateVersion,
          'ops': [again],
        },
      ),
    );
    final results = (answer as ApiOk).json['results']! as List<Object?>;
    expect(results.single, {
      'client_txn_id': again['client_txn_id'],
      'status': 'rejected',
      'reason': 'already_granted',
    });
    // Nothing more given.
    final after = await _state(device);
    expect(after.wallet.fuel, before.wallet.fuel);
    expect(after.wallet.bonat, before.wallet.bonat);
    expect(after.wallet.jenehat, before.wallet.jenehat);
  });

  test(
    'a filtered name comes back refused, and the phone asks again',
    () async {
      final device = await e2eDevice();
      final engine = e2eEngine(device);
      final rejected = <OpRejected>[];
      engine.events.listen((event) {
        if (event is OpRejected) rejected.add(event);
      });
      final economy = device.economy.service;
      expect(await device.account.ensureSession(), isTrue);

      expect(
        await economy.setDisplayName(economy.newRequestId(), _filtered),
        isA<OpApplied>(),
      );
      expect(economy.view.displayName, _filtered);
      await engine.syncNow();
      expect(economy.pendingCount, 0, reason: '${engine.snapshot.lastError}');

      expect(rejected.single.opType, 'settings_update');
      expect(rejected.single.reason, 'validation_error');
      expect(economy.view.nameRefused, isTrue);
      expect(economy.view.displayName, isNull);
      expect((await _state(device)).displayName, isNull);
    },
  );
}
