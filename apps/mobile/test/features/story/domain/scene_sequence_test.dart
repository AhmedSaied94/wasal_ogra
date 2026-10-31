// M10's scene sequence (specs/015-m10-apartment-story, contracts/
// scene-viewer.md "Routes", T078): a chapter's unlocked scenes in story
// order.
import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/content/domain/content_source.dart';
import 'package:wassal/core/progress/domain/player_progress.dart';
import 'package:wassal/features/story/domain/scene_sequence.dart';

import '../../../helpers/progress.dart';

List<String> _ids(ContentSource content, Chapter chapter, PlayerProgress p) => [
  for (final scene in sceneSequence(content, p, chapter)) scene.sceneId,
];

void main() {
  test('one scene: the chapter\'s only unlocked one', () {
    final content = sampleWith((_) {});
    final chapter = content.chapter(ChapterId.ch1FirstJob)!;
    // The opening is always playable; the after-trip one waits for the trip.
    expect(_ids(content, chapter, player()), ['opening']);
  });

  test('a chapter\'s unlocked scenes in story order', () {
    final content = sampleWith((_) {});
    final chapter = content.chapter(ChapterId.ch1FirstJob)!;
    expect(
      _ids(content, chapter, player({'line_hay.01': 1, 'line_hay.03': 3})),
      ['opening', 'the_stand'],
    );
  });

  test('nothing unlocked: an empty sequence', () {
    final content = sampleWith((_) {});
    // chapter 2's goal scene needs chapter 1 met; chapter 4's needs the room.
    final locked = content.chapter(ChapterId.ch2HerFather)!;
    expect(_ids(content, locked, player()), isEmpty);
    final room = content.chapter(ChapterId.ch4Salon)!;
    expect(_ids(content, room, player(hayDone)), isEmpty);
  });
}
