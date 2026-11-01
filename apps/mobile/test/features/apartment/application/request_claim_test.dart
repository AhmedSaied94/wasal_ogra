// Taking a family request's reward (specs/015-m10-apartment-story, contracts/
// apartment.md "Family requests", T111): rules first, one held id per
// request, and a refusal that leaves the request in the list.
import 'dart:async';

import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/economy/economy.dart';
import 'package:wassal/core/progress/application/player_progress_provider.dart';
import 'package:wassal/core/progress/domain/player_progress.dart';
import 'package:wassal/core/progress/domain/requests.dart';
import 'package:wassal/features/apartment/application/request_claim.dart';

import '../../../helpers/economy.dart';
import '../../../helpers/progress.dart';

final class _FakeEconomy implements Economy {
  _FakeEconomy(this.outcomes);

  final List<FutureOr<OpOutcome>> outcomes;
  final calls = <(TxnId, String)>[];
  var _next = 300;

  @override
  TxnId newRequestId() => txnIdOf(_next++);

  @override
  Future<OpOutcome> claimRequest(TxnId id, {required String requestId}) async {
    calls.add((id, requestId));
    return outcomes.removeAt(0);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

late final LedgerOp _anyOp;
late final EconomyView _anyView;

OpApplied _applied() => OpApplied(op: _anyOp, view: _anyView, repeated: false);

/// The shabka bought and the salon open, the nish owned.
PlayerProgress _owning() => player(hayDone, {microOld, shabka, salonNish});

String? _crystal(String itemId) => itemId == 'salon.nish' ? 'crystal' : null;

String? _classic(String itemId) => itemId == 'salon.nish' ? 'classic' : null;

void main() {
  final content = artboardSalonContent();
  final nish = content.familyRequests.firstWhere(
    (r) => r.requestId == 'req_nish_crystal',
  );

  setUpAll(() async {
    final e = await testEconomy(
      content: content,
      firstState: (nowMs) => EconomyState.newPlayer(
        fuelMax: 5,
        nowMs: nowMs,
      ).copyWith(jenehat: 10000),
    );
    final outcome = await e.service.buy(
      e.service.newRequestId(),
      kind: SkuKind.item,
      skuId: 'salon.nish',
      variantId: 'classic',
    ) as OpApplied;
    _anyOp = outcome.op;
    _anyView = outcome.view;
    await e.db.close();
  });

  Future<RequestClaimResult> claim(
    RequestClaim claimer, {
    PlayerProgress? progress,
    String? Function(String)? variantOf,
    Set<String> claimed = const {},
  }) => claimer.claim(
    nish,
    progress: progress ?? _owning(),
    variantOf: variantOf ?? _crystal,
    requestsClaimed: claimed,
  );

  test('the rules come first: only a done request sends a claim', () async {
    final economy = _FakeEconomy([]);
    final claimer = RequestClaim(economy, content);
    final refused = <String, RequestClaimResult>{
      'locked': await claim(claimer, progress: PlayerProgress.empty),
      'open': await claim(
        claimer,
        progress: player(hayDone, {microOld, shabka}),
      ),
      'missed': await claim(claimer, variantOf: _classic),
      'claimed': await claim(claimer, claimed: {nish.requestId}),
    };
    for (final MapEntry(:key, :value) in refused.entries) {
      expect(value, isA<RequestNotAllowed>(), reason: key);
    }
    expect(economy.calls, isEmpty);
  });

  test('a request with no style named is done in any style', () async {
    final economy = _FakeEconomy([_applied()]);
    final claimer = RequestClaim(economy, content);
    final plain = FamilyRequest(
      requestId: nish.requestId,
      roomId: nish.roomId,
      itemId: nish.itemId,
      character: nish.character,
      text: nish.text,
      rewardBonat: nish.rewardBonat,
    );
    final result = await claimer.claim(
      plain,
      progress: _owning(),
      variantOf: _classic,
      requestsClaimed: const {},
    );
    expect(result, isA<RequestClaimed>());
    expect(economy.calls.single.$2, nish.requestId);
  });

  test('one held id per request: a failed write keeps it, an answer clears '
      'it', () async {
    final economy = _FakeEconomy([
      const OpWriteFailed(),
      const OpWriteFailed(),
      const OpRefused(EconomyRefusal.notEligible),
      _applied(),
    ]);
    final claimer = RequestClaim(economy, content);
    for (var i = 0; i < 3; i++) {
      await claim(claimer);
    }
    expect(economy.calls[0].$1, economy.calls[1].$1);
    expect(
      economy.calls[2].$1,
      economy.calls[1].$1,
      reason: 'the second failure kept it, so the third tap reuses it',
    );
    await claim(claimer);
    expect(
      economy.calls[3].$1,
      isNot(economy.calls[2].$1),
      reason: 'a refusal is an answer: the next intent is new',
    );
  });

  test('a double tap claims once (SC-002)', () async {
    final gate = Completer<OpOutcome>();
    final economy = _FakeEconomy([gate.future]);
    final claimer = RequestClaim(economy, content);
    final first = claim(claimer);
    expect(claimer.busyWith(nish.requestId), isTrue);
    final second = await claim(claimer);
    expect(second, isA<RequestNotAllowed>());
    gate.complete(_applied());
    expect(await first, isA<RequestClaimed>());
    expect(economy.calls, hasLength(1));
    expect(claimer.busyWith(nish.requestId), isFalse);
  });

  test('a server refusal returns the request to the list', () async {
    final economy = _FakeEconomy([const OpRefused(EconomyRefusal.notEligible)]);
    final claimer = RequestClaim(economy, content);
    final result = await claim(claimer);
    expect(result, isA<RequestRefused>());
    expect((result as RequestRefused).code, EconomyRefusal.notEligible);
    // Nothing was added to the claimed set, so the same inputs still list
    // it as done: M06's rollback of a refused claim leaves it as it was.
    expect(
      requestState(content, _owning(), nish, _crystal, const {}),
      RequestState.done,
    );
  });

  test('the real economy: a claim records the id and moves no balance '
      '(constitution IV)', () async {
    final e = await testEconomy(
      content: content,
      firstState: (nowMs) =>
          EconomyState.newPlayer(fuelMax: 5, nowMs: nowMs).copyWith(
            jenehat: 10000,
            progress: {
              for (final id in hayDone.keys)
                id: const TripProgress(bestStars: 1, plays: 1),
            },
            ownership: {
              (SkuKind.vehicle, 'micro_old'): Owned(
                kind: SkuKind.vehicle,
                acquiredAtMs: 0,
              ),
              (SkuKind.chapter, 'ch3_shabka'): Owned(
                kind: SkuKind.chapter,
                acquiredAtMs: 0,
              ),
              (SkuKind.item, 'salon.nish'): Owned(
                kind: SkuKind.item,
                acquiredAtMs: 0,
                variantId: 'crystal',
              ),
            },
          ),
    );
    addTearDown(e.close);
    final claimer = RequestClaim(e.service, content);
    final view = e.service.view;
    final before = playerProgressOf(view, content);
    final bonat = view.bonat;
    final jenehat = view.jenehat;

    final result = await claimer.claim(
      nish,
      progress: before,
      variantOf: view.variantOf,
      requestsClaimed: view.requestsClaimed,
    );
    expect(result, isA<RequestClaimed>());
    expect(e.service.view.requestsClaimed, {nish.requestId});
    expect(e.service.view.bonat, bonat);
    expect(e.service.view.jenehat, jenehat);

    final again = await claimer.claim(
      nish,
      progress: before,
      variantOf: e.service.view.variantOf,
      requestsClaimed: e.service.view.requestsClaimed,
    );
    expect(again, isA<RequestNotAllowed>());
  });
}
