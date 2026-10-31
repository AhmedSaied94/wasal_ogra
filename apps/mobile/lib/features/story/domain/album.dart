// The album's cards (specs/015-m10-apartment-story, contracts/scene-viewer.md
// "The album", research R13, Q3): one per scene of the pack in story order,
// the unlocked ones to watch again and the locked ones as a tease. Pure.
import 'package:content_models/content_models.dart';
import 'package:wassal/core/content/domain/content_source.dart';
import 'package:wassal/core/progress/domain/player_progress.dart';
import 'package:wassal/core/progress/domain/story.dart';
import 'package:wassal/features/story/domain/panel_ref.dart';

sealed class AlbumCard {
  const AlbumCard({required this.chapterNumber});

  /// The chapter's `order`, as the viewer's top bar shows it.
  final int chapterNumber;
}

/// A scene the player may watch: seen or still waiting.
final class UnlockedCard extends AlbumCard {
  const UnlockedCard({
    required super.chapterNumber,
    required this.scene,
    required this.firstPanel,
  });

  final Scene scene;
  final PanelRef firstPanel;
}

/// A scene not yet unlocked: its title still shows (the design teases the
/// story), and the card is inert.
final class LockedCard extends AlbumCard {
  const LockedCard({
    required super.chapterNumber,
    required this.sceneId,
    required this.title,
  });

  final String sceneId;
  final String title;
}

/// Every scene of [c] as a card for [p], and how many are unlocked of how
/// many. A waiting scene counts unlocked: the economy's seen set plays no
/// part.
(List<AlbumCard>, int, int) album(ContentSource c, PlayerProgress p) {
  final cards = <AlbumCard>[];
  var unlocked = 0;
  for (final (chapter, scene) in scenesInStoryOrder(c)) {
    if (sceneUnlocked(c, p, chapter, scene)) {
      unlocked++;
      cards.add(
        UnlockedCard(
          chapterNumber: chapter.order,
          scene: scene,
          firstPanel: PanelRef.of(scene.panels.first),
        ),
      );
    } else {
      cards.add(
        LockedCard(
          chapterNumber: chapter.order,
          sceneId: scene.sceneId,
          title: scene.title.arEg,
        ),
      );
    }
  }
  return (cards, unlocked, cards.length);
}
