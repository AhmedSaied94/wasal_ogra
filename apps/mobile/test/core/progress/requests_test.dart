// The family requests (specs/015-m10-apartment-story, data-model.md "Family
// request"): each state, the badge's count, and the list's order.
import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/content/domain/content_source.dart';
import 'package:wassal/core/progress/domain/player_progress.dart';
import 'package:wassal/core/progress/domain/requests.dart';

import '../../helpers/economy.dart';

ContentSource _content() => sampleContent();

/// A player who met chapters 1 to 3's goals, so the salon's chapter is
/// unlocked: the line finished, the microbus owned, the shabka bought.
PlayerProgress _atChapterFour(ContentSource c) => PlayerProgress(
  bestStars: {for (final trip in c.tripsOf(LineId.lineHay)) trip.tripId: 1},
  owned: const {
    (SkuKind.vehicle, 'micro_old'),
    (SkuKind.chapter, 'ch3_shabka'),
  },
);

/// The same, owning the nish too.
PlayerProgress _owning(ContentSource c) => PlayerProgress(
  bestStars: _atChapterFour(c).bestStars,
  owned: {..._atChapterFour(c).owned, (SkuKind.item, 'salon.nish')},
);

String? Function(String) _noStyle = (_) => null;

void main() {
  final c = _content();
  final request = c.familyRequests.firstWhere(
    (r) => r.requestId == 'req_nish_crystal',
  );

  test('locked until its room\'s chapter unlocks', () {
    expect(
      requestState(c, PlayerProgress.empty, request, _noStyle, const {}),
      RequestState.locked,
    );
  });

  test('open while the piece is not owned', () {
    expect(
      requestState(c, _atChapterFour(c), request, _noStyle, const {}),
      RequestState.open,
    );
  });

  test('done when the piece is owned, in the style it names', () {
    expect(
      requestState(c, _owning(c), request, (_) => 'crystal', const {}),
      RequestState.done,
    );
  });

  test('done with no style named, in any style', () {
    final owns = _owning(c);
    final plain = FamilyRequest(
      requestId: request.requestId,
      roomId: request.roomId,
      itemId: request.itemId,
      character: request.character,
      text: request.text,
      rewardBonat: request.rewardBonat,
    );
    expect(
      requestState(c, owns, plain, (_) => 'classic', const {}),
      RequestState.done,
    );
  });

  test('missed when the piece is owned in another style', () {
    expect(
      requestState(c, _owning(c), request, (_) => 'classic', const {}),
      RequestState.missed,
    );
  });

  test('claimed wins over done and missed', () {
    expect(
      requestState(c, _atChapterFour(c), request, _noStyle, {
        request.requestId,
      }),
      RequestState.claimed,
    );
  });

  test('openRequestCount is open plus done', () {
    expect(
      openRequestCount(c, PlayerProgress.empty, _noStyle, const {}),
      0,
      reason: 'its chapter is locked',
    );
    expect(openRequestCount(c, _atChapterFour(c), _noStyle, const {}), 1);
    expect(
      openRequestCount(c, _atChapterFour(c), _noStyle, {request.requestId}),
      0,
    );
  });

  test('requestStates: done first, then the rooms\' and items\' order', () {
    final rows = requestStates(c, _atChapterFour(c), _noStyle, const {});
    expect(rows.map((r) => r.$1.requestId), [request.requestId]);
    expect(rows.single.$2, RequestState.open);
  });

  test('the sample has one request, and its state is the only row', () {
    expect(c.familyRequests, hasLength(1));
  });
}
