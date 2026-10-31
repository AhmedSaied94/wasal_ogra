// The story riders, for screen readers (specs/015-m10-apartment-story,
// contracts/story-trip.md "Riders in the scene"): each rider's seat says
// «{name} راكب معاك» once. The riders themselves are the Flame scene's; this
// layer draws nothing and takes no taps.
import 'package:content_models/content_models.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/content/domain/story_characters.dart';
import 'package:wassal/features/trip/domain/scene_layout.dart';
import 'package:wassal/features/trip/presentation/trip_scope.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

class RiderLabels extends StatelessWidget {
  const RiderLabels({required this.layout, super.key});

  final SceneLayout layout;

  static Key keyOf(String seatId) => ValueKey('trip-rider-$seatId');

  @override
  Widget build(BuildContext context) {
    final riders =
        TripScope.of(context).controller.session?.facts.storyInfo?.riders ??
        const <StoryRider>[];
    final l10n = AppLocalizations.of(context);
    return IgnorePointer(
      child: Stack(
        children: [
          for (final rider in riders)
            if (layout.seats[rider.seat] case final seat?)
              Positioned(
                left: seat.hit.left,
                top: seat.hit.top,
                width: seat.hit.width,
                height: seat.hit.height,
                child: Semantics(
                  key: keyOf(rider.seat),
                  container: true,
                  label: l10n.tripRiderA11y(
                    l10n.sceneSpeaker(storyCharacterArt(rider.character)),
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
        ],
      ),
    );
  }
}
