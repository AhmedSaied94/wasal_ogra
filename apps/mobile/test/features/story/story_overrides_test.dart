// M10's slot overrides (specs/015-m10-apartment-story, contracts/story-flow.md
// "Changes to merged code"): a waiting scene makes the savings card say so.
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/features/home/application/home_slots.dart';

import '../../helpers/first_session.dart';
import '../../helpers/lines.dart';

void main() {
  testWidgets('nothing waiting: the slot is false', (tester) async {
    // The opening scene is seen, and nothing else is unlocked.
    final (container, _) = await pumpLinesApp(
      tester,
      state: playerState(
        scenesSeen: const {
          'ch1_first_job': {'opening'},
        },
      ),
    );
    expect(container.read(storySceneWaitingProvider), isFalse);
  });

  testWidgets('the opening M07 recorded on its own: no scene waits', (
    tester,
  ) async {
    // M07 writes the opening to `first_session` before the projection has it
    // (research R3): the savings card keeps its bar, not the waiting text.
    final (container, _) = await pumpLinesApp(
      tester,
      newPlayer: true,
      overrides: [
        ...seededFirstSession((store) async {
          await store.markOpeningDone(0);
          await store.markSceneSeen('opening');
        }),
      ],
    );
    expect(container.read(storySceneWaitingProvider), isFalse);
  });

  testWidgets('a scene waiting: the slot is true', (tester) async {
    // The first trip finished on the phone, its after-trip scene not played.
    final (container, _) = await pumpLinesApp(
      tester,
      state: playerState(stars: {'line_hay.03': 1}),
    );
    expect(container.read(storySceneWaitingProvider), isTrue);
  });
}
