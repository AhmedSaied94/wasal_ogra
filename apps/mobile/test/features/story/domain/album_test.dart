// The album's cards (specs/015-m10-apartment-story, contracts/scene-viewer.md
// "The album", T100): one card per scene of the pack in story order, a
// waiting scene counted unlocked, and the count.
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/features/story/domain/album.dart';
import 'package:wassal/features/story/domain/panel_ref.dart';

import '../../../helpers/progress.dart';

void main() {
  final content = sampleWith((_) {});

  test('one card per scene, in story order, with the chapter\'s number', () {
    final (cards, _, total) = album(content, player());
    expect(total, 4);
    expect(cards, hasLength(4));
    expect(
      [
        for (final card in cards)
          switch (card) {
            UnlockedCard(:final scene) => scene.sceneId,
            LockedCard(:final sceneId) => sceneId,
          },
      ],
      ['opening', 'the_stand', 'father_visit', 'family_visit'],
    );
    expect([for (final card in cards) card.chapterNumber], [1, 1, 2, 4]);
  });

  test('a new player has the opening only', () {
    final (cards, unlocked, total) = album(content, player());
    expect(unlocked, 1);
    expect(total, 4);
    expect(cards.first, isA<UnlockedCard>());
    expect(cards.skip(1), everyElement(isA<LockedCard>()));
  });

  test('a locked card still shows its title: the album teases the story', () {
    final (cards, _, _) = album(content, player());
    final locked = cards.last as LockedCard;
    expect(locked.title, 'العيلة في الصالون');
    expect(locked.chapterNumber, 4);
  });

  test('an unlocked card carries the first panel\'s art', () {
    final (cards, _, _) = album(content, player());
    final opening = cards.first as UnlockedCard;
    expect(
      opening.firstPanel,
      const PanelRef(art: 'opening_key', speakers: ['narrator', 'moallem']),
    );
    expect(opening.scene.title.arEg, 'المفتاح');
  });

  test('a scene waiting to be seen counts unlocked', () {
    // Chapter 2 is complete, so its goal scene is unlocked, seen or not.
    final p = player({...hayDone, 'line_hay.03': 1}, {microOld});
    final (cards, unlocked, total) = album(content, p);
    expect(unlocked, 3);
    expect(total, 4);
    expect(
      [
        for (final card in cards)
          if (card is UnlockedCard) card.scene.sceneId,
      ],
      ['opening', 'the_stand', 'father_visit'],
    );
  });

  test('a story trip\'s scene needs the trip finished', () {
    final p = player({'line_hay.01': 1, 'line_hay.02': 1});
    final (cards, _, _) = album(content, p);
    expect(cards[1], isA<LockedCard>());
    final after = album(content, player({'line_hay.03': 1}));
    expect(after.$1[1], isA<UnlockedCard>());
  });

  test('every scene unlocked: the count is the total', () {
    final p = player(hayDone, {microOld, shabka, salonNish, salonSitara});
    final (cards, unlocked, total) = album(content, p);
    expect(unlocked, 3);
    // `the_stand` waits for line_hay.03, which the story trip finishes.
    final finished = player(
      {...hayDone, 'line_hay.03': 1},
      {microOld, shabka, salonNish, salonSitara},
    );
    final all = album(content, finished);
    expect(all.$2, all.$3);
    expect(all.$2, total);
    expect(cards.whereType<LockedCard>(), hasLength(1));
  });

  test('a pack with no scenes has an empty album', () {
    final bare = sampleWith((json) {
      for (final chapter in entries(json, 'chapters')) {
        chapter['scenes'] = <Object?>[];
      }
    });
    final (cards, unlocked, total) = album(bare, player());
    expect(cards, isEmpty);
    expect(unlocked, 0);
    expect(total, 0);
  });
}
