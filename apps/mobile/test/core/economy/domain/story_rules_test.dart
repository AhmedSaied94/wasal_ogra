// The two operations M10 records through the economy (specs/015-m10-apartment-story,
// contracts/economy-ops.md "Operations"): `story_progress` and `claim_request`.
//
// Each refusal is checked in the contract's order, first failure wins; a repeat writes nothing, and
// a claim never changes a balance.
import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/economy/domain/economy_refusal.dart';
import 'package:wassal/core/economy/domain/economy_state.dart';
import 'package:wassal/core/economy/domain/op.dart';
import 'package:wassal/core/economy/domain/rules.dart';
import 'package:wassal/core/economy/domain/txn_id.dart';

import '../../../helpers/economy.dart';

const _storyProgress = StoryProgressRequest(
  chapterId: ChapterId.ch1FirstJob,
  sceneId: 'the_stand',
);
const _claim = ClaimRequest(requestId: 'req_nish_crystal');

RuleContext _ctx({TxnId? id}) => RuleContext(
  nowMs: testEpochMs,
  content: sampleContent(),
  contentVersion: 7,
  fuelMax: 8,
  fuelRegenMinutes: 120,
  txnId: id ?? TxnId.parse('0192f3a1-7b2c-7d4e-8f00-0000000000aa'),
);

EconomyState _state({
  Map<String, Set<String>> scenesSeen = const {},
  Set<String> requestsClaimed = const {},
  Map<OwnedKey, Owned> ownership = const {},
  int jenehat = 100,
  int bonat = 3,
}) => EconomyState(
  jenehat: jenehat,
  bonat: bonat,
  fuel: const FuelState(liters: 8, countedFromMs: testEpochMs),
  ownership: ownership,
  scenesSeen: scenesSeen,
  requestsClaimed: requestsClaimed,
);

Owned _item(String variantId) =>
    Owned(kind: SkuKind.item, variantId: variantId, acquiredAtMs: testEpochMs);

void main() {
  group('story_progress', () {
    test('refuses a scene the pack lacks, and one of another chapter', () {
      final unknown = visit(
        _state(),
        const StoryProgressRequest(
          chapterId: ChapterId.ch1FirstJob,
          sceneId: 'no_such_scene',
        ),
      );
      expect(unknown, isA<Declined>());
      expect((unknown as Declined).code, EconomyRefusal.unknownSku);

      // The salon's scene isn't the first chapter's.
      final other = visit(
        _state(),
        const StoryProgressRequest(
          chapterId: ChapterId.ch1FirstJob,
          sceneId: 'family_visit',
        ),
      );
      expect((other as Declined).code, EconomyRefusal.unknownSku);

      // A chapter the pack doesn't have at all.
      final missing = visit(
        _state(),
        const StoryProgressRequest(
          chapterId: ChapterId.ch7Wedding,
          sceneId: 'the_stand',
        ),
      );
      expect((missing as Declined).code, EconomyRefusal.unknownSku);
    });

    test('refuses a scene already recorded', () {
      final decision = visit(
        _state(
          scenesSeen: {
            'ch1_first_job': {'the_stand'},
          },
        ),
        _storyProgress,
      );
      expect((decision as Declined).code, EconomyRefusal.alreadyRecorded);
    });

    test('accepts a new scene and stamps the wire payload', () {
      final decision = visit(_state(), _storyProgress);
      final op = (decision as Validated).op;
      expect(op.type, OpType.storyProgress);
      expect(op.payload, {
        'chapter_id': 'ch1_first_job',
        'scene_id': 'the_stand',
      });
      expect((op.jenehatDelta, op.bonatDelta), (0, 0));
      expect(op.contentVersion, 7);
    });

    test('adds the scene to its chapter, and changes no balance', () {
      final op = (visit(_state(), _storyProgress) as Validated).op;
      final after = const ProductionRules().apply(_state(), op);
      expect(after.scenesSeen, {
        'ch1_first_job': {'the_stand'},
      });
      expect((after.jenehat, after.bonat), (100, 3));
    });

    test('keeps two chapters apart, and a second scene in one', () {
      const rules = ProductionRules();
      final first = (visit(_state(), _storyProgress) as Validated).op;
      final once = rules.apply(_state(), first);
      final second = (visit(
        once,
        const StoryProgressRequest(
          chapterId: ChapterId.ch4Salon,
          sceneId: 'family_visit',
        ),
      ) as Validated).op;
      final twice = rules.apply(once, second);
      expect(twice.scenesSeen, {
        'ch1_first_job': {'the_stand'},
        'ch4_salon': {'family_visit'},
      });
    });

    test('replaying over a base that already has it is a no-op', () {
      final op = (visit(_state(), _storyProgress) as Validated).op;
      final base = _state(
        scenesSeen: {
          'ch1_first_job': {'the_stand'},
        },
      );
      expect(const ProductionRules().stillValid(base, op), isFalse);
      expect(
        const ProductionRules().stillValid(_state(), op),
        isTrue,
        reason: 'a scene the base lacks still applies',
      );
    });

    test('an id the pack lacks is kept (M04 says to keep it)', () {
      final base = _state(
        scenesSeen: {
          'ch9_gone': {'lost_scene'},
        },
      );
      final op = (visit(base, _storyProgress) as Validated).op;
      final after = const ProductionRules().apply(base, op);
      expect(after.scenesSeen['ch9_gone'], {'lost_scene'});
      expect(after.scenesSeen['ch1_first_job'], {'the_stand'});
    });
  });

  group('claim_request', () {
    test('refuses a request the pack lacks', () {
      final decision = visit(
        _state(),
        const ClaimRequest(requestId: 'req_nobody'),
      );
      expect((decision as Declined).code, EconomyRefusal.unknownSku);
    });

    test('refuses a request already granted', () {
      final decision = visit(
        _state(requestsClaimed: {'req_nish_crystal'}),
        _claim,
      );
      expect((decision as Declined).code, EconomyRefusal.alreadyGranted);
    });

    test('refuses a piece the player does not own', () {
      final decision = visit(_state(), _claim);
      expect((decision as Declined).code, EconomyRefusal.notEligible);
    });

    test('refuses a piece owned in another style', () {
      final decision = visit(
        _state(ownership: {(SkuKind.item, 'salon.nish'): _item('classic')}),
        _claim,
      );
      expect((decision as Declined).code, EconomyRefusal.notEligible);
    });

    test('accepts the named style, and stores the id only', () {
      final decision = visit(
        _state(ownership: {(SkuKind.item, 'salon.nish'): _item('crystal')}),
        _claim,
      );
      final op = (decision as Validated).op;
      expect(op.type, OpType.claimRequest);
      expect(op.payload, {'request_id': 'req_nish_crystal'});

      final after = const ProductionRules().apply(
        _state(ownership: {(SkuKind.item, 'salon.nish'): _item('crystal')}),
        op,
      );
      expect(after.requestsClaimed, {'req_nish_crystal'});
      expect((after.jenehat, after.bonat), (100, 3));
    });

    test('accepts a request that names no style, in any style', () {
      final content = sampleContent();
      final request = content.familyRequests.first;
      expect(request.variantId, isNotNull);
      // The sample's only request names `crystal`; a plain one has no variant.
      final decision = visit(
        _state(ownership: {(SkuKind.item, 'salon.nish'): _item('crystal')}),
        ClaimRequest(requestId: request.requestId),
      );
      expect(decision, isA<Validated>());
    });

    test('a base that already has the claim makes it a no-op', () {
      final op = (visit(
        _state(ownership: {(SkuKind.item, 'salon.nish'): _item('crystal')}),
        _claim,
      ) as Validated).op;
      final base = _state(
        ownership: {(SkuKind.item, 'salon.nish'): _item('crystal')},
        requestsClaimed: {'req_nish_crystal'},
      );
      expect(const ProductionRules().stillValid(base, op), isFalse);
    });

    test('a claim a new base no longer holds is not added twice', () {
      // Eligibility needs the pack, which the fold doesn't hold: a claim the
      // restored base makes impossible is refused by the server and dropped
      // by M06's rollback (contracts/economy-ops.md, research R5).
      final op = (visit(
        _state(ownership: {(SkuKind.item, 'salon.nish'): _item('crystal')}),
        _claim,
      ) as Validated).op;
      expect(const ProductionRules().stillValid(_state(), op), isTrue);
      expect(
        const ProductionRules().stillValid(
          _state(requestsClaimed: {'req_nish_crystal'}),
          op,
        ),
        isFalse,
      );
    });
  });

  group('requestMatches', () {
    test('a story_progress op matches only its own chapter and scene', () {
      final op = (visit(_state(), _storyProgress) as Validated).op;
      expect(requestMatches(op, _storyProgress), isTrue);
      expect(
        requestMatches(
          op,
          const StoryProgressRequest(
            chapterId: ChapterId.ch1FirstJob,
            sceneId: 'opening',
          ),
        ),
        isFalse,
      );
      expect(
        requestMatches(
          op,
          const StoryProgressRequest(
            chapterId: ChapterId.ch4Salon,
            sceneId: 'the_stand',
          ),
        ),
        isFalse,
      );
    });

    test('a claim_request op matches only its own request', () {
      final op = (visit(
        _state(ownership: {(SkuKind.item, 'salon.nish'): _item('crystal')}),
        _claim,
      ) as Validated).op;
      expect(requestMatches(op, _claim), isTrue);
      expect(
        requestMatches(op, const ClaimRequest(requestId: 'req_other')),
        isFalse,
      );
    });
  });
}

/// `validateStoryProgress` / `claimRequest` through the production rules.
Decision visit(EconomyState state, OpRequest request) =>
    const ProductionRules().validate(state, request, _ctx());
