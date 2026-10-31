@Tags(['backend'])
library;

import 'dart:convert';

import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/economy/economy.dart' hide Owned;
import 'package:wassal/core/economy/economy_service.dart';
import 'package:wassal/core/network/api_client.dart';
import 'package:wassal/core/progress/application/player_progress_provider.dart';
import 'package:wassal/core/progress/domain/rewards.dart';
import 'package:wassal/core/sync/domain/wire/state.dart';
import 'package:wassal/features/apartment/application/goal_purchase.dart';
import 'package:wassal/features/apartment/application/piece_purchase.dart';

import '../helpers/economy.dart';
import 'backend_shell.dart';
import 'e2e.dart';

// The apartment and the story against the dev stack (specs/015-m10-apartment-
// story, T098, SC-004, quickstart §6): a player with the coins plays the
// sample's line_hay, buys the old microbus, the shabka and the salon's two
// pieces, sees every scene and takes the nish's request, all offline, then
// syncs. The server accepts every operation (none comes back `not_unlocked`),
// pays the rooms', chapters' and request's BONAT the phone only showed as on
// its way, and a fresh install of the same account restores all of it with
// nothing left pending.

/// A trip on the sample's line_hay: its start and its result.
Future<void> _play(EconomyService economy, String tripId) async {
  final start = economy.newRequestId();
  expect(await economy.startTrip(start, tripId: tripId), isA<OpApplied>());
  expect(
    await economy.recordResult(
      economy.newRequestId(),
      start: start,
      result: tripResult(
        tripId: tripId,
        stars: 2,
        earnings: 12,
        durationMs: 60000,
      ),
    ),
    isA<OpApplied>(),
  );
}

Future<void> _see(
  EconomyService economy,
  ChapterId chapter,
  String sceneId,
) async {
  expect(
    await economy.recordScene(
      economy.newRequestId(),
      chapterId: chapter,
      sceneId: sceneId,
    ),
    isA<OpApplied>(),
    reason: sceneId,
  );
}

Future<StateSnapshot> _state(E2eDevice device) async {
  final answer = await device.account.authorized.send(
    const ApiRequest.get(ApiPaths.state, receiveTimeout: readReceiveTimeout),
  );
  return StateSnapshot.fromJson((answer as ApiOk).json);
}

/// The scenes the server holds, by chapter.
Map<String, Set<String>> _scenesOf(StateSnapshot state) => {
  for (final chapter in state.story.chapters)
    if (chapter.scenesSeen.isNotEmpty)
      chapter.chapterId: chapter.scenesSeen.toSet(),
};

void main() {
  setUpAll(useRealHttp);

  test('the apartment and the story sync, pay once and restore', () async {
    final device = await e2eDevice();
    // Ahead of any base: the first pass takes the full state, staff's
    // coins with it (as offline_sync_test.dart).
    int? serverVersion = 1 << 30;
    final engine = e2eEngine(device, serverStateVersion: () => serverVersion);
    final economy = device.economy.service;
    final content = device.economy.content;

    // Online once: the account, coins for the old microbus (1,500), the
    // shabka (900) and the salon (400 + 150), and the state with them.
    expect(await device.account.ensureSession(), isTrue);
    final player = device.account.playerId!;
    await grantJenehat(player, 5000);
    await engine.syncNow();
    serverVersion = null;
    expect(economy.view.jenehat, 5000);
    expect(economy.view.bonat, 0);

    // Offline. Chapter 1: the line, the opening, the story trip and its scene.
    await _see(economy, ChapterId.ch1FirstJob, 'opening');
    await _play(economy, 'line_hay.01');
    await _play(economy, 'line_hay.02');
    await _play(economy, 'line_hay.03');
    await _see(economy, ChapterId.ch1FirstJob, 'the_stand');

    // Chapter 2: the microbus, then her father's visit.
    expect(
      await economy.buy(
        economy.newRequestId(),
        kind: SkuKind.vehicle,
        skuId: 'micro_old',
      ),
      isA<OpApplied>(),
    );
    await _see(economy, ChapterId.ch2HerFather, 'father_visit');

    // Chapter 3: the shabka, from the apartment's goal card.
    final shabka = content.chapters.firstWhere(
      (c) => c.chapterId == ChapterId.ch3Shabka,
    );
    expect(
      await GoalPurchase(economy)
          .buy(content, playerProgressOf(economy.view, content), shabka),
      isA<GoalBought>(),
    );

    // Chapter 4: the salon, the nish in crystal so the request can be taken.
    final pieces = PiecePurchase(economy, content);
    for (final (itemId, variant) in const [
      ('salon.sitara', 'plain'),
      ('salon.nish', 'crystal'),
    ]) {
      final bought = await pieces.buy(
        content.item(itemId)!,
        variant,
        before: playerProgressOf(economy.view, content),
      );
      expect(bought.outcome, isA<OpApplied>(), reason: itemId);
    }
    await _see(economy, ChapterId.ch4Salon, 'family_visit');
    expect(
      await economy.claimRequest(
        economy.newRequestId(),
        requestId: 'req_nish_crystal',
      ),
      isA<OpApplied>(),
    );

    // The phone shows the rewards as on their way and adds none (IV).
    List<PendingReward> pending() => pendingRewards(
      content,
      playerProgressOf(economy.view, content),
      playerProgressOfConfirmed(economy.view.confirmed, content),
      economy.view.requestsClaimed,
      economy.view.confirmed.requestsClaimed,
    );
    final owed = pending();
    expect(
      [for (final reward in owed) reward.source],
      [
        const RoomReward(RoomId.salon),
        const ChapterReward(ChapterId.ch1FirstJob),
        const ChapterReward(ChapterId.ch2HerFather),
        const ChapterReward(ChapterId.ch3Shabka),
        const ChapterReward(ChapterId.ch4Salon),
        const RequestReward('req_nish_crystal'),
      ],
    );
    final owedBonat = pendingTotal(owed);
    expect(owedBonat, greaterThan(0));
    expect(economy.view.bonat, 0);
    final queued = economy.pendingCount;
    expect(queued, greaterThan(0));

    await engine.syncNow();
    expect(economy.pendingCount, 0, reason: '${engine.snapshot.lastError}');

    // Every operation accepted, none refused as locked.
    final processed = await backendShell('''
import json
from apps.economy.models import ProcessedOp
rows = ProcessedOp.objects.filter(player_id="$player")
print(json.dumps([[r.status, r.reason] for r in rows]))
''');
    final rows = (jsonDecode(processed.trim().split('\n').last) as List)
        .cast<List<Object?>>();
    expect(rows, hasLength(queued));
    expect([for (final row in rows) row.first], everyElement('accepted'));
    expect([for (final row in rows) row.last], isNot(contains('not_unlocked')));

    // The server paid what the phone showed, once.
    final server = await _state(device);
    expect(server.wallet.bonat, owedBonat);
    expect(economy.view.bonat, server.wallet.bonat);
    expect(economy.view.jenehat, server.wallet.jenehat);
    expect(pending(), isEmpty);
    expect(server.story.requestsClaimed, ['req_nish_crystal']);
    final seen = {
      'ch1_first_job': {'opening', 'the_stand'},
      'ch2_her_father': {'father_visit'},
      'ch4_salon': {'family_visit'},
    };
    expect(_scenesOf(server), seen);
    expect(economy.view.scenesSeen, seen);
    expect(economy.view.variantOf('salon.nish'), 'crystal');
    expect(economy.view.variantOf('salon.sitara'), 'plain');

    // A fresh install of the same account takes it all, and shows nothing
    // on its way.
    final restored = await e2eDevice(installIds: device.installIds);
    expect(await restored.account.ensureSession(), isTrue);
    expect(restored.account.playerId, player);
    int? restoreVersion = 1 << 30;
    await e2eEngine(
      restored,
      serverStateVersion: () => restoreVersion,
    ).syncNow();
    restoreVersion = null;
    final view = restored.economy.service.view;
    expect(view.bonat, owedBonat);
    expect(view.scenesSeen, seen);
    expect(view.requestsClaimed, {'req_nish_crystal'});
    expect(view.owns(SkuKind.vehicle, 'micro_old'), isTrue);
    expect(view.owns(SkuKind.chapter, 'ch3_shabka'), isTrue);
    expect(view.variantOf('salon.nish'), 'crystal');
    expect(view.variantOf('salon.sitara'), 'plain');
    expect(
      pendingRewards(
        restored.economy.content,
        playerProgressOf(view, restored.economy.content),
        playerProgressOfConfirmed(view.confirmed, restored.economy.content),
        view.requestsClaimed,
        view.confirmed.requestsClaimed,
      ),
      isEmpty,
    );
  });
}
