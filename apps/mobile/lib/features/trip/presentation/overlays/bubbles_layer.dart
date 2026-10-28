// What passengers say (layer 8, HANDOFF §3.4 `SpeechBubble`, drawn by
// core/theme/components/characters.dart): the newest two
// bubbles, each with its tail's tip 8 pt above the speaker's head, the body
// kept 10 pt inside the scene (and under the strips at its top), at
// 16 pt and never scaled. A bubble pops from its tail; it just appears under
// reduced motion.
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/components/characters.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/trip/domain/scene_layout.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';
import 'package:wassal/features/trip/presentation/overlays/story_strip.dart';
import 'package:wassal/features/trip/presentation/trip_scope.dart';

/// Bubbles keep this far inside the scene.
const bubbleMargin = 10.0;

/// A story trip's condition strip covers the scene's top this far.
const storyBand = 56.0;

/// The scene's top that [strips] strips cover (a story trip's condition,
/// the fast-forward notice), each 8 pt below the last.
double stripsBand(int strips) => strips == 0
    ? 0
    : SpaceTokens.s8 + strips * (StoryStrip.height + SpaceTokens.s8);

/// At most this many bubbles show; older ones wait.
const maxBubbles = 2;

/// Two bubbles keep this far apart.
const _gap = 6.0;

/// The variant of a passenger's bubble style.
SpeechBubbleVariant variantOf(BubbleStyle style) => switch (style) {
  BubbleStyle.plain => SpeechBubbleVariant.normal,
  BubbleStyle.warning => SpeechBubbleVariant.warn,
  BubbleStyle.fight => SpeechBubbleVariant.fight,
  BubbleStyle.thanks => SpeechBubbleVariant.thanks,
};

typedef _Said = ({BubbleView bubble, String seatId});

class BubblesLayer extends StatelessWidget {
  const BubblesLayer({required this.layout, super.key});

  final SceneLayout layout;

  @override
  Widget build(BuildContext context) {
    return MediaQuery.withNoTextScaling(
      child: TripSelector<(List<_Said>, int)>(
        select: (model) {
          final view = model.view;
          if (view == null) return (const [], 0);
          final newest = [...view.bubbles]
            ..sort((a, b) => a.shownAtMs.compareTo(b.shownAtMs));
          return (
            [
              for (final b in newest.skip(max(0, newest.length - maxBubbles)))
                if (view.passenger(b.passengerId)?.seatId case final seat?)
                  (bubble: b, seatId: seat),
            ],
            (view.storyCondition != null ? 1 : 0) + (view.fastForward ? 1 : 0),
          );
        },
        equals: (a, b) => a.$2 == b.$2 && listEquals(a.$1, b.$1),
        builder: (context, selected) {
          final (said, strips) = selected;
          final shown = [
            for (final s in said)
              if (layout.seats[s.seatId] case final seat?)
                (
                  said: s,
                  tip: Offset(seat.bubbleAnchor.x, seat.bubbleAnchor.y),
                ),
          ];
          return CustomMultiChildLayout(
            delegate: _BubbleLayout(
              tips: [for (final s in shown) s.tip],
              minTop: stripsBand(strips) + bubbleMargin,
            ),
            children: [
              for (final (i, s) in shown.indexed) ...[
                LayoutId(
                  id: (_Part.body, i),
                  child: SpeechBubble(
                    key: ValueKey(
                      'bubble-${s.said.bubble.passengerId}-'
                      '${s.said.bubble.shownAtMs}',
                    ),
                    text: s.said.bubble.text,
                    variant: variantOf(s.said.bubble.style),
                    tail: false,
                  ),
                ),
                LayoutId(
                  id: (_Part.tail, i),
                  child: BubblePop(
                    child: SpeechBubbleTail(
                      variant: variantOf(s.said.bubble.style),
                      tipKey: SpeechBubble.tailKey(s.said.bubble.passengerId),
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

enum _Part { body, tail }

/// Each body over its tail's tip, clamped inside the margins; a second
/// body that would overlap the first moves above it, or beside it.
class _BubbleLayout extends MultiChildLayoutDelegate {
  _BubbleLayout({required this.tips, required this.minTop});

  final List<Offset> tips;
  final double minTop;

  @override
  void performLayout(Size size) {
    final placed = <Rect>[];
    for (final (i, tip) in tips.indexed) {
      final body = layoutChild(
        (_Part.body, i),
        BoxConstraints.loose(
          Size(max(0, size.width - 2 * bubbleMargin), size.height),
        ),
      );
      final tailCentre = tip.dy - bubbleTailHalfDiagonal;
      double left(double x) => x.clamp(
        bubbleMargin,
        max(bubbleMargin, size.width - bubbleMargin - body.width),
      );
      var rect = Rect.fromLTWH(
        left(tip.dx - body.width / 2),
        max(minTop, tailCentre + bubbleTailInset - body.height),
        body.width,
        body.height,
      );
      for (final other in placed) {
        if (!rect.overlaps(other.inflate(_gap / 2))) continue;
        final above = other.top - _gap - body.height;
        if (above >= minTop) {
          rect = Rect.fromLTWH(rect.left, above, body.width, body.height);
          continue;
        }
        final right = other.right + _gap;
        final x = right + body.width <= size.width - bubbleMargin
            ? right
            : max(bubbleMargin, other.left - _gap - body.width);
        rect = Rect.fromLTWH(x, rect.top, body.width, body.height);
      }
      placed.add(rect);
      positionChild((_Part.body, i), rect.topLeft);
      layoutChild((
        _Part.tail,
        i,
      ), BoxConstraints.tight(const Size.square(DesignExtras.bubbleTail)));
      positionChild(
        (_Part.tail, i),
        Offset(
          tip.dx - DesignExtras.bubbleTail / 2,
          tailCentre - DesignExtras.bubbleTail / 2,
        ),
      );
    }
  }

  @override
  bool shouldRelayout(_BubbleLayout oldDelegate) =>
      !listEquals(oldDelegate.tips, tips) || oldDelegate.minTop != minTop;
}
