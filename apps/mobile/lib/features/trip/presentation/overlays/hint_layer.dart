// بلية's hint (layer 8, research R12, HANDOFF `Tutorial` blocks 5–7): his
// head at the scene's bottom corner by the door, his line beside it in a
// character bubble with his name, and the coach's hand pointing at the
// passenger it is about. No scrim: the hint takes no touch (the screen wraps
// it in an IgnorePointer), so everything under it still answers. While a
// popover is open in the scene, it moves to the top corner. When it shows
// and what it says are M02's.
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/components/story.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/trip/domain/scene_layout.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';
import 'package:wassal/features/trip/presentation/overlays/bubbles_layer.dart';
import 'package:wassal/core/theme/components/characters.dart';
import 'package:wassal/features/trip/presentation/trip_scope.dart';
import 'package:wassal/features/trip/presentation/trip_text.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

/// What the hint layer draws: the line, the seat it points at, whether a
/// popover is open in the scene, and whether a story strip tops it.
typedef _Shown = ({String text, String? seatId, bool popover, bool story});

/// `Tutorial` blocks 5–6 against the scene's bottom-right corner: his head
/// 6 in and 22 up; his bubble 14 from the left, 104 from the right, 2
/// above his head.
const _headRight = 6.0;
const _headBottom = 22.0;
const _bubbleLeft = 14.0;
const _bubbleRight = 104.0;
const _bubbleAboveHead = 2.0;

/// How far the tail's square pokes past the bubble's edge.
const _tailOut = 7.0;

class HintLayer extends StatelessWidget {
  const HintLayer({required this.layout, super.key});

  final SceneLayout layout;

  static const headKey = ValueKey('trip-hint-head');
  static const bubbleKey = ValueKey('trip-hint-bubble');
  static const pointerKey = ValueKey('trip-hint-pointer');

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return TripSelector<_Shown?>(
      select: (model) {
        final view = model.view;
        final hint = view?.hint;
        final text = hint == null ? null : l10n.hintText(hint.key);
        if (view == null || hint == null || text == null) return null;
        final target = hint.targetPassengerId;
        return (
          text: text,
          seatId: target == null ? null : view.passenger(target)?.seatId,
          popover: view.choices.any(
            (c) => c is ClaimChoice || c is ChangeRequestChoice,
          ),
          story: view.storyStrip != null,
        );
      },
      builder: (context, shown) {
        if (shown == null) return const SizedBox.shrink();
        // A popover hangs under a face, and the false claimer's hint comes
        // with his: while one is open, بلية moves to the scene's top
        // corner, clear of every row's popover (below a story strip).
        final headTop = shown.popover
            ? (shown.story ? storyBand : SpaceTokens.s8) + _bubbleAboveHead
            : BelyaSays.headTopIn(layout.height);
        final face = layout.seats[shown.seatId]?.head;
        final target = face == null
            ? null
            : Rect.fromLTWH(face.left, face.top, face.width, face.height);
        // The hand points up from under its target, as `Tutorial` draws it,
        // unless there it would cover بلية's words or a popover under the
        // face; then it points down from above.
        final band = Rect.fromLTRB(
          _bubbleLeft,
          headTop - _bubbleAboveHead,
          layout.width - _headRight,
          headTop + CharacterAvatar.size.height,
        );
        Offset? hand;
        var down = false;
        if (target != null) {
          final below = CoachHand.placeFor(target) & CoachHand.size;
          down = shown.popover || below.overlaps(band);
          hand = down ? CoachHand.placeAbove(target) : below.topLeft;
        }
        return Stack(
          children: [
            Positioned.fill(
              child: BelyaSays(
                text: shown.text,
                name: l10n.tripHintSpeaker,
                headTop: headTop,
                semanticsLabel: l10n.tripHintSemantics(shown.text),
                headKey: headKey,
                bubbleKey: bubbleKey,
              ),
            ),
            if (hand case final hand?)
              Positioned(
                left: hand.dx,
                top: hand.dy,
                child: down
                    ? const CoachHand.down(key: pointerKey)
                    : const CoachHand(key: pointerKey),
              ),
          ],
        );
      },
    );
  }
}

/// بلية and his line (`Tutorial` blocks 5–6), laid over the scene: his head
/// [headTop] down at the door, his bubble beside it. M02's hints and M07's
/// coach both speak through it. With no [semanticsLabel] it is silent to
/// screen readers (the coach announces its lines).
class BelyaSays extends StatelessWidget {
  const BelyaSays({
    required this.text,
    required this.name,
    required this.headTop,
    this.semanticsLabel,
    this.headKey,
    this.bubbleKey,
    super.key,
  });

  final String text;
  final String name;
  final double headTop;
  final String? semanticsLabel;
  final Key? headKey;
  final Key? bubbleKey;

  /// His head's top against a scene [height]: at its bottom corner.
  static double headTopIn(double height) =>
      height - _headBottom - CharacterAvatar.size.height;

  @override
  Widget build(BuildContext context) {
    final bubble = Stack(
      clipBehavior: Clip.none,
      children: [
        SpeechBubble(
          key: bubbleKey,
          text: text,
          name: name,
          variant: SpeechBubbleVariant.character,
          tail: false,
          padding: DesignExtras.hintBubblePadding,
          quoteStyle: DesignExtras.hintQuote,
          scaled: true,
        ),
        const Positioned(
          right: -_tailOut,
          bottom: DesignExtras.hintTailRise,
          child: _Tail(),
        ),
      ],
    );
    final label = semanticsLabel;
    // Physical sides: the door is on the right in either direction, and
    // بلية stands at it.
    return Stack(
      children: [
        Positioned(
          right: _headRight,
          top: headTop,
          child: KeyedSubtree(
            key: headKey,
            child: const CharacterAvatar('belya'),
          ),
        ),
        Positioned(
          left: _bubbleLeft,
          right: _bubbleRight,
          top: headTop - _bubbleAboveHead,
          child: label == null
              ? ExcludeSemantics(child: bubble)
              : Semantics(
                  liveRegion: true,
                  label: label,
                  excludeSemantics: true,
                  child: bubble,
                ),
        ),
      ],
    );
  }
}

/// The bubble's tail toward بلية: a 16 pt square turned 45°, its rounded
/// corner the tip.
class _Tail extends StatelessWidget {
  const _Tail();

  @override
  Widget build(BuildContext context) => Transform.rotate(
    angle: 0.7853981633974483,
    child: const SizedBox.square(
      dimension: DesignExtras.hintTail,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: ColorTokens.paper,
          borderRadius: BorderRadius.only(
            topRight: Radius.circular(DesignExtras.hintTailRadius),
          ),
        ),
      ),
    ),
  );
}
