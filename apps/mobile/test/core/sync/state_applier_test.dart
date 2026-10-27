import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/content/domain/content_source.dart';
import 'package:wassal/core/sync/domain/wire/state.dart';
import 'package:wassal/core/sync/state_applier.dart';
import 'package:wassal/core/sync/sync_engine.dart';
import 'package:wassal/features/trip/data/drift_trip_records.dart';

import '../../helpers/economy.dart';
import '../../helpers/sync.dart';

// Taking the server's state (specs/011-m06-identity-sync, contracts/
// sync.md "Taking the full state"): a restore at launch runs alongside the
// content step, so the applier waits for the pack instead of reading it.

void main() {
  test('waits for the pack when it has not loaded yet', () async {
    final e = await testEconomy();
    final pack = Completer<ContentSource>();
    final applier = ServerStateApplier(
      economy: e.service,
      trips: DriftTripRecords(e.db),
      content: () => pack.future,
      writeProfile: ({displayName, driverLevel}) async {},
    );

    var done = false;
    final applying = applier
        .apply(
          StateSnapshot.fromJson(stateJson(stateVersion: 8)),
          StateWhy.firstOpen,
          playerId: syncPlayer,
          sentAtElapsedMs: 0,
          receivedAtElapsedMs: 0,
        )
        .whenComplete(() => done = true);
    await pumpEventQueue();
    expect(done, isFalse);
    expect(e.service.baseInfo.stateVersion, isNull);

    pack.complete(e.content);
    await applying;
    expect(e.service.baseInfo, (stateVersion: 8, playerId: syncPlayer));
  });
}
