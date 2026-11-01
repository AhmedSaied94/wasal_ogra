// The two operations the story records (specs/015-m10-apartment-story,
// contracts/economy-ops.md "Operations", research R5): a scene seen, and a
// family request claimed. Neither changes a balance on the phone: the
// server's grant arrives through M06 (constitution IV).
//
// The chapter's unlock is the caller's rule: this domain may not import
// `core/progress/domain/`, so `story_progress` trusts `StoryService` to call
// it only for a scene that isn't locked, and the server still refuses
// `not_unlocked` through M06's rollback.
import 'package:content_models/content_models.dart';
import 'package:wassal/core/content/domain/content_source.dart';
import 'package:wassal/core/economy/domain/economy_refusal.dart';
import 'package:wassal/core/economy/domain/economy_state.dart';
import 'package:wassal/core/economy/domain/op.dart';
import 'package:wassal/core/economy/domain/rules.dart';
import 'package:wassal/core/economy/domain/wire.dart';

/// The chapter's scene named [sceneId], or null.
Scene? _scene(ContentSource content, ChapterId chapterId, String sceneId) {
  for (final scene in content.chapter(chapterId)?.scenes ?? const <Scene>[]) {
    if (scene.sceneId == sceneId) return scene;
  }
  return null;
}

Decision validateStoryProgress(
  EconomyState s,
  StoryProgressRequest request,
  RuleContext ctx,
) {
  if (_scene(ctx.content, request.chapterId, request.sceneId) == null) {
    return const Declined(EconomyRefusal.unknownSku);
  }
  final chapter = chapterWire[request.chapterId]!;
  if (s.scenesSeen[chapter]?.contains(request.sceneId) ?? false) {
    return const Declined(EconomyRefusal.alreadyRecorded);
  }
  return Validated(
    ctx.op(OpType.storyProgress, {
      'chapter_id': chapter,
      'scene_id': request.sceneId,
    }),
  );
}

EconomyState applyStoryProgress(EconomyState s, Op op) {
  final chapter = op.string('chapter_id');
  final scene = op.string('scene_id');
  return s.copyWith(
    scenesSeen: {
      ...s.scenesSeen,
      chapter: {...?s.scenesSeen[chapter], scene},
    },
  );
}

/// A scene the new base already has is a no-op, and a scene it lacks still
/// applies. Ids the active pack lacks are kept (M04's rule).
bool storyProgressStillValid(EconomyState s, Op op) =>
    !(s.scenesSeen[op.string('chapter_id')]?.contains(op.string('scene_id')) ??
        false);

Decision validateClaimRequest(
  EconomyState s,
  ClaimRequest request,
  RuleContext ctx,
) {
  final wanted = request.requestId;
  FamilyRequest? found;
  for (final candidate in ctx.content.familyRequests) {
    if (candidate.requestId == wanted) {
      found = candidate;
      break;
    }
  }
  if (found == null) return const Declined(EconomyRefusal.unknownSku);
  if (s.requestsClaimed.contains(wanted)) {
    return const Declined(EconomyRefusal.alreadyGranted);
  }
  final owned = s.ownership[(SkuKind.item, found.itemId)];
  if (owned == null) return const Declined(EconomyRefusal.notEligible);
  final variant = found.variantId;
  if (variant != null && owned.variantId != variant) {
    return const Declined(EconomyRefusal.notEligible);
  }
  return Validated(ctx.op(OpType.claimRequest, {'request_id': wanted}));
}

/// A claim only ever adds the request's id (M10 FR-024): the BONAT is the
/// server's, and no balance moves here.
EconomyState applyClaimRequest(EconomyState s, Op op) => s.copyWith(
  requestsClaimed: {...s.requestsClaimed, op.string('request_id')},
);

/// A claim the new base already has is a no-op. A claim that is no longer
/// eligible — the piece gone in a restored base — is refused by the server
/// and dropped by M06's rollback, so it isn't rechecked here: doing so would
/// need the content, which the fold doesn't hold (research R5).
bool claimRequestStillValid(EconomyState s, Op op) =>
    !s.requestsClaimed.contains(op.string('request_id'));
