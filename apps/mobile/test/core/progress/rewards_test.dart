// The rewards on their way (specs/015-m10-apartment-story,
// contracts/economy-ops.md "Pending rewards", research R6).
import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/content/domain/content_source.dart';
import 'package:wassal/core/progress/domain/player_progress.dart';
import 'package:wassal/core/progress/domain/rewards.dart';

import '../../helpers/economy.dart';

ContentSource _content() => sampleContent();

/// A salon complete, in any styles: every item the room holds, and the three
/// chapters before it done.
PlayerProgress _salonDone(ContentSource c) => PlayerProgress(
  bestStars: {for (final trip in c.tripsOf(LineId.lineHay)) trip.tripId: 1},
  owned: {
    (SkuKind.vehicle, 'micro_old'),
    (SkuKind.chapter, 'ch3_shabka'),
    for (final item in c.itemsOf(RoomId.salon)) (SkuKind.item, item.itemId),
  },
);

void main() {
  final c = _content();

  test('an empty base marks every completion pending', () {
    final done = _salonDone(c);
    final rewards = pendingRewards(
      c,
      done,
      PlayerProgress.empty,
      const {},
      const {},
    );

    expect(
      rewards.map((r) => r.source),
      contains(const RoomReward(RoomId.salon)),
    );
    expect(
      rewards.map((r) => r.source),
      contains(const ChapterReward(ChapterId.ch4Salon)),
    );
    final room = c.room(RoomId.salon)!;
    expect(
      rewards
          .firstWhere((r) => r.source == const RoomReward(RoomId.salon))
          .bonat,
      room.completionBonat,
    );
  });

  test('a room completing its chapter yields two rewards', () {
    final done = _salonDone(c);
    final rewards = pendingRewards(
      c,
      done,
      PlayerProgress.empty,
      const {},
      const {},
    );
    expect(
      rewards.where(
        (r) =>
            r.source == const RoomReward(RoomId.salon) ||
            r.source == const ChapterReward(ChapterId.ch4Salon),
      ),
      hasLength(2),
    );
  });

  test('then received once the confirmed progress has it', () {
    final done = _salonDone(c);
    expect(pendingRewards(c, done, done, const {}, const {}), isEmpty);
  });

  test('a request is pending from the claim to the base', () {
    const claimed = {'req_nish_crystal'};
    var rewards = pendingRewards(
      c,
      PlayerProgress.empty,
      PlayerProgress.empty,
      claimed,
      const {},
    );
    expect(rewards.single.source, const RequestReward('req_nish_crystal'));
    expect(rewards.single.bonat, c.familyRequests.first.rewardBonat);

    rewards = pendingRewards(
      c,
      PlayerProgress.empty,
      PlayerProgress.empty,
      claimed,
      claimed,
    );
    expect(rewards, isEmpty);
  });

  test('a rolled-back purchase yields none', () {
    // The projection is the confirmed base: nothing is on its way.
    final done = _salonDone(c);
    expect(pendingRewards(c, done, done, const {}, const {}), isEmpty);
    expect(
      pendingRewards(c, PlayerProgress.empty, done, const {}, const {}),
      isEmpty,
    );
  });

  test('pendingTotal sums the rewards', () {
    final done = _salonDone(c);
    final rewards = pendingRewards(
      c,
      done,
      PlayerProgress.empty,
      const {},
      const {},
    );
    expect(pendingTotal(rewards), rewards.fold(0, (s, r) => s + r.bonat));
    expect(pendingTotal(const []), 0);
  });
}
