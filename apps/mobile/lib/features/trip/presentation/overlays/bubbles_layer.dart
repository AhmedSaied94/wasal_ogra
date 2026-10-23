// What passengers say (layer 8, HANDOFF §3.4 `SpeechBubble`): the newest two
// bubbles, each with its tail's tip 8 pt above the speaker's head, the body
// kept 10 pt inside the scene (and under a story trip's 56 pt band), at
// 16 pt and never scaled. A bubble pops from its tail; it just appears under
// reduced motion.
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/trip/domain/scene_layout.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';
import 'package:wassal/features/trip/presentation/trip_motion.dart';
import 'package:wassal/features/trip/presentation/trip_scope.dart';

/// Bubbles keep this far inside the scene.
const bubbleMargin = 10.0;

/// A story trip's condition strip covers the scene's top this far.
const storyBand = 56.0;

/// At most this many bubbles show; older ones wait.
const maxBubbles = 2;

/// Two bubbles keep this far apart.
const _gap = 6.0;

enum SpeechBubbleVariant { normal, warn, fight, thanks, character }

/// The variant of a passenger's bubble style.
SpeechBubbleVariant variantOf(BubbleStyle style) => switch (style) {
  BubbleStyle.plain => SpeechBubbleVariant.normal,
  BubbleStyle.warning => SpeechBubbleVariant.warn,
  BubbleStyle.fight => SpeechBubbleVariant.fight,
  BubbleStyle.thanks => SpeechBubbleVariant.thanks,
};

typedef _BubbleColors = ({Color bg, Color text, BoxShadow lip});

_BubbleColors _colorsOf(SpeechBubbleVariant variant) => switch (variant) {
  SpeechBubbleVariant.normal || SpeechBubbleVariant.character => (
    bg: ColorTokens.paper,
    text: ColorTokens.ink,
    lip: LipTokens.bubble,
  ),
  SpeechBubbleVariant.warn => (
    bg: ColorTokens.dangerSoft,
    text: ColorTokens.ink,
    lip: LipTokens.bubbleWarn,
  ),
  SpeechBubbleVariant.fight => (
    bg: ColorTokens.danger,
    text: ColorTokens.ink,
    lip: DesignExtras.bubbleFightLip,
  ),
  SpeechBubbleVariant.thanks => (
    bg: ColorTokens.primarySoft,
    text: ColorTokens.primary,
    lip: LipTokens.bubble,
  ),
};

/// The tail: a 14 pt square turned 45°, poking 6 pt below the body.
const _tailHalfDiagonal = DesignExtras.bubbleTail * 0.7071067811865476;

/// How far the body's bottom sits above the tail square's centre.
const _tailInset = DesignExtras.bubbleTail / 2 - 6;

/// A speech bubble; on its own it draws its tail under its middle.
class SpeechBubble extends StatelessWidget {
  const SpeechBubble({
    required this.text,
    this.variant = SpeechBubbleVariant.normal,
    this.name,
    this.tail = true,
    this.padding,
    this.quoteStyle,
    this.scaled = false,
    super.key,
  });

  final String text;
  final SpeechBubbleVariant variant;

  /// The speaker's name over a character's line.
  final String? name;

  /// A character bubble's own padding and line style (بلية's hint).
  final EdgeInsets? padding;
  final TextStyle? quoteStyle;

  /// Whether its text follows the system's scale up to 1.3 (the hint, as
  /// cards do); passengers' bubbles never scale.
  final bool scaled;

  /// Whether to draw the tail; the scene places it at the speaker.
  final bool tail;

  static Key tailKey(String passengerId) =>
      ValueKey('bubble-tail-$passengerId');

  @override
  Widget build(BuildContext context) {
    final colors = _colorsOf(variant);
    final character = variant == SpeechBubbleVariant.character;
    final scaler = scaled
        ? MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3)
        : TextScaler.noScaling;
    final line = TypeTokens.bubble.copyWith(color: colors.text, height: 1.35);
    final body = DecoratedBox(
      decoration: BoxDecoration(
        color: colors.bg,
        borderRadius: BorderRadius.all(
          Radius.circular(
            character
                ? DesignExtras.characterBubbleRadius
                : RadiusTokens.bubble,
          ),
        ),
        boxShadow: [colors.lip],
      ),
      child: Padding(
        padding:
            padding ??
            (character
                ? DesignExtras.characterBubblePadding
                : DesignExtras.bubblePadding),
        child: character
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (name case final name?)
                    Text(
                      name,
                      textScaler: scaler,
                      style: TypeTokens.label
                          .weight(700)
                          .copyWith(color: ColorTokens.inkMuted),
                    ),
                  Text(
                    text,
                    textScaler: scaler,
                    style: (quoteStyle ?? TypeTokens.quote).copyWith(
                      color: colors.text,
                    ),
                  ),
                ],
              )
            : Text(text, textScaler: TextScaler.noScaling, style: line),
      ),
    );
    final bubble = tail
        ? Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.bottomCenter,
            children: [
              body,
              Positioned(
                bottom: _tailInset - DesignExtras.bubbleTail / 2,
                child: SpeechBubbleTail(variant: variant),
              ),
            ],
          )
        : body;
    return BubblePop(child: bubble);
  }
}

/// A bubble's tail, in its variant's colour. The [tipKey] goes on the
/// turned square, so its rect's bottom is the tip.
class SpeechBubbleTail extends StatelessWidget {
  const SpeechBubbleTail({required this.variant, this.tipKey, super.key});

  final SpeechBubbleVariant variant;
  final Key? tipKey;

  @override
  Widget build(BuildContext context) => Transform.rotate(
    angle: pi / 4,
    child: SizedBox.square(
      key: tipKey,
      dimension: DesignExtras.bubbleTail,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _colorsOf(variant).bg,
          borderRadius: const BorderRadius.only(
            bottomRight: Radius.circular(DesignExtras.bubbleTailRadius),
          ),
        ),
      ),
    ),
  );
}

/// Pops [child] from 0.6 to its size, from the bottom, once; under reduced
/// motion it just appears.
class BubblePop extends StatelessWidget {
  const BubblePop({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.6, end: 1),
      duration: TripMotion.bubblePop,
      curve: TripMotion.bubblePopCurve,
      builder: (context, scale, child) => Transform.scale(
        scale: scale,
        alignment: Alignment.bottomCenter,
        child: child,
      ),
      child: child,
    );
  }
}

typedef _Said = ({BubbleView bubble, String seatId});

class BubblesLayer extends StatelessWidget {
  const BubblesLayer({required this.layout, super.key});

  final SceneLayout layout;

  @override
  Widget build(BuildContext context) {
    return MediaQuery.withNoTextScaling(
      child: TripSelector<(List<_Said>, bool)>(
        select: (model) {
          final view = model.view;
          if (view == null) return (const [], false);
          final newest = [...view.bubbles]
            ..sort((a, b) => a.shownAtMs.compareTo(b.shownAtMs));
          return (
            [
              for (final b in newest.skip(max(0, newest.length - maxBubbles)))
                if (view.passenger(b.passengerId)?.seatId case final seat?)
                  (bubble: b, seatId: seat),
            ],
            view.storyCondition != null,
          );
        },
        equals: (a, b) => a.$2 == b.$2 && listEquals(a.$1, b.$1),
        builder: (context, selected) {
          final (said, story) = selected;
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
              minTop: story ? storyBand + bubbleMargin : bubbleMargin,
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
      final tailCentre = tip.dy - _tailHalfDiagonal;
      double left(double x) => x.clamp(
        bubbleMargin,
        max(bubbleMargin, size.width - bubbleMargin - body.width),
      );
      var rect = Rect.fromLTWH(
        left(tip.dx - body.width / 2),
        max(minTop, tailCentre + _tailInset - body.height),
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
