@Tags(['backend'])
library;

import 'dart:convert';

import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/economy/economy.dart' hide Owned;
import 'package:wassal/core/progress/application/player_progress_provider.dart';
import 'package:wassal/core/progress/domain/playable.dart';
import 'package:wassal/features/lines/application/vehicle_purchase.dart';
import 'package:wassal/features/lines/domain/vehicle_offer.dart';

import 'backend_shell.dart';
import 'e2e.dart';

// Lines' path against the dev stack (specs/014-m09-lines-vehicles, T081,
// SC-003): a player with the coins buys the old microbus offline, as the
// vehicle sheet does, starts خط الجامعة's first trip, and syncs. Both
// operations are accepted, and none comes back `not_unlocked`: the phone
// offered nothing the server refuses.

void main() {
  setUpAll(useRealHttp);

  test('the microbus and خط الجامعة\'s first trip are accepted', () async {
    final device = await e2eDevice();
    // Ahead of any base: the first pass takes the full state, staff's
    // coins with it (as offline_sync_test.dart).
    int? serverVersion = 1 << 30;
    final engine = e2eEngine(device, serverStateVersion: () => serverVersion);
    final economy = device.economy.service;
    final content = device.economy.content;

    // Online once: the account, staff's coins, and the state with them.
    expect(await device.account.ensureSession(), isTrue);
    final player = device.account.playerId!;
    await grantJenehat(player, 2000);
    await engine.syncNow();
    serverVersion = null;
    expect(economy.view.jenehat, 2000);

    // Offline: the purchase, as the sheet makes it.
    final offer = vehicleOffer(
      content,
      playerProgressOf(economy.view, content),
      economy.view.jenehat,
      VehicleId.microOld,
    )!;
    expect(offer.sale, isA<ForSale>());
    final bought = await VehiclePurchase(economy).buy(offer);
    expect(bought, isA<OpApplied>());

    // The line's first trip, playable on the phone now.
    final progress = playerProgressOf(economy.view, content);
    expect(tripPlayable(content, progress, 'line_gamaa.01'), isTrue);
    expect(
      await economy.startTrip(economy.newRequestId(), tripId: 'line_gamaa.01'),
      isA<OpApplied>(),
    );

    await engine.syncNow();
    expect(economy.pendingCount, 0, reason: '${engine.snapshot.lastError}');

    final processed = await backendShell('''
import json
from apps.economy.models import ProcessedOp
rows = ProcessedOp.objects.filter(player_id="$player")
print(json.dumps([[r.status, r.reason] for r in rows]))
''');
    final rows = (jsonDecode(processed.trim().split('\n').last) as List)
        .cast<List<Object?>>();
    expect(rows, hasLength(2));
    expect([for (final row in rows) row.first], everyElement('accepted'));
    expect([for (final row in rows) row.last], isNot(contains('not_unlocked')));
    expect(economy.view.owns(SkuKind.vehicle, 'micro_old'), isTrue);
  });
}
