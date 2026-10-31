// The fast-forward notice: once nothing is left for the player, the clock
// runs `settledSpeedUp` times faster to the end of the line, and this strip
// says why. The design has no such strip, so it takes the story strip's
// look (HANDOFF `StoryTrip` block 3, like `OfflineBanner`): dark, 40 high,
// radius 14, white 12/600 text after two `play` glyphs in `sun` that point
// the way the microbus goes. It sits at the scene's top, under a story
// trip's strip, fades in, and is announced once. Bubbles keep below it
// (`stripsBand`).
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/components/app_icon.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/trip/presentation/overlays/story_strip.dart';
import 'package:wassal/features/trip/presentation/trip_scope.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

class FastForwardStrip extends StatelessWidget {
  const FastForwardStrip({super.key});

  static const stripKey = ValueKey('trip-fast-forward');

  @override
  Widget build(BuildContext context) {
    return TripSelector<(bool, bool)>(
      select: (model) {
        final view = model.view;
        return (view?.fastForward ?? false, view?.storyStrip != null);
      },
      builder: (context, shown) {
        final (on, story) = shown;
        return Padding(
          padding: EdgeInsets.only(
            top: story ? StoryStrip.height + SpaceTokens.s8 : 0,
          ),
          child: AnimatedOpacity(
            opacity: on ? 1 : 0,
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : MotionTokens.toast,
            curve: MotionTokens.toastCurve,
            child: on ? const _Strip(key: stripKey) : const SizedBox.shrink(),
          ),
        );
      },
    );
  }
}

class _Strip extends StatelessWidget {
  const _Strip({super.key});

  static const double _glyph = 16;

  @override
  Widget build(BuildContext context) {
    final text = AppLocalizations.of(context).tripFastForward;
    const glyph = AppIcon('play', size: _glyph, color: ColorTokens.sun);
    return Semantics(
      liveRegion: true,
      label: text,
      excludeSemantics: true,
      child: Container(
        height: StoryStrip.height,
        padding: const EdgeInsets.symmetric(horizontal: SpaceTokens.s12),
        decoration: BoxDecoration(
          color: ColorTokens.dashboardBg,
          borderRadius: BorderRadius.circular(StoryStrip.radius),
        ),
        child: Row(
          spacing: SpaceTokens.s8,
          children: [
            Transform.flip(
              flipX: Directionality.of(context) == TextDirection.rtl,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [glyph, glyph],
              ),
            ),
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TypeTokens.caption
                    .weight(600)
                    .copyWith(color: ColorTokens.paper),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
