// A restore (specs/015-m10-apartment-story, spec FR-052–FR-054, T096): the
// server's state replaces the phone's, and the apartment, the scenes seen and
// the claims come back, with nothing playing by itself.
import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/economy/economy.dart' show TripProgress;
import 'package:wassal/core/economy/economy_providers.dart';
import 'package:wassal/core/progress/application/pending_rewards_provider.dart';
import 'package:wassal/core/progress/domain/story.dart';
import 'package:wassal/features/apartment/presentation/pending_chip.dart';
import 'package:wassal/features/apartment/presentation/room_done_dialog.dart';
import 'package:wassal/features/story/presentation/scene_viewer_page.dart';
import 'package:wassal/features/story/story_overrides.dart';
import 'package:wassal/core/content/content_providers.dart';
import 'package:wassal/core/progress/application/player_progress_provider.dart';
import 'package:wassal/features/onboarding/domain/first_session.dart';
import 'package:wassal/features/onboarding/onboarding_providers.dart';

import '../../helpers/lines.dart';
import '../../helpers/progress.dart';
import '../../helpers/synthetic_packs.dart';

void main() {
  testWidgets('the apartment, the scenes and the claims come back; nothing '
      'plays by itself', (tester) async {
    final (container, economy) = await pumpLinesApp(
      tester,
      pack: artboardSalon(),
      location: '/apartment',
    );
    // The server's state: «المعلم»'s trip finished, the shabka and two salon
    // pieces in their styles, one scene seen and one request taken.
    // Its trips carry best times and no first finish, as the server's do.
    final server =
        playerState(
          owned: {microOld, shabka, salonNish, salonSitara},
          styles: const {'salon.nish': 'classic', 'salon.sitara': 'plain'},
          scenesSeen: const {
            'ch1_first_job': {'opening'},
          },
        )(0).copyWith(
          requestsClaimed: const {'req_nish_crystal'},
          progress: {
            for (final trip in [...hayDone.keys, 'line_hay.03'])
              trip: const TripProgress(
                bestStars: 1,
                plays: 1,
                bestTimeMs: 60000,
              ),
          },
        );
    await tester.runAsync(
      () => economy.service.replaceFromServer(
        server,
        playerId: 'p-restored',
        stateVersion: 9,
      ),
    );
    await tester.pumpAndSettle();

    final view = container.read(economyViewProvider);
    // The pieces, in their styles.
    expect(view.owns(SkuKind.item, 'salon.nish'), isTrue);
    expect(view.variantOf('salon.nish'), 'classic');
    expect(view.variantOf('salon.sitara'), 'plain');
    // What was seen and claimed.
    expect(view.scenesSeen, {
      'ch1_first_job': {'opening'},
    });
    expect(view.requestsClaimed, {'req_nish_crystal'});

    // `the_stand` and chapter 2's goal scene are unlocked and not seen: they
    // wait, and nothing is due.
    final content = container.read(contentSourceProvider);
    final waiting = waitingScenes(
      content,
      container.read(playerProgressProvider),
      seenScenesOf(
        content,
        view,
        container.read(firstSessionFlagsProvider).value ??
            FirstSessionFlags.empty,
      ),
    );
    expect(
      [for (final (_, scene) in waiting) scene.sceneId],
      ['the_stand', 'father_visit'],
    );
    expect(container.read(firstSessionProvider).dueScene, isNull);
    expect(find.byType(SceneViewerPage), findsNothing);
    expect(find.byType(RoomDoneDialog), findsNothing);

    // The server has all of it: nothing is on its way.
    expect(container.read(pendingRewardsProvider), isEmpty);
    // Nothing pending, so the header has no chip at all.
    expect(find.byType(PendingChip), findsNothing);
    expect(locationOf(container), '/apartment');
  });
}
