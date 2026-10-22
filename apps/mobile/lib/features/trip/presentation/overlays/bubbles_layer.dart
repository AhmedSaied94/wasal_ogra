// What passengers say (layer 8): at most two bubbles, above the speaker's
// head with the tail toward them, kept inside the scene with 8 pt margins,
// at most 60% of its width, at 15 pt and never scaled
// (contracts/scene-layout.md "Bubbles").
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/app_theme.dart';
import 'package:wassal/core/theme/tokens/shape.dart';
import 'package:wassal/core/theme/tokens/typography.dart';
import 'package:wassal/features/trip/domain/scene_layout.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';
import 'package:wassal/features/trip/presentation/trip_motion.dart';
import 'package:wassal/features/trip/presentation/trip_scope.dart';

const bubbleMargin = 8.0;
const bubbleMaxShare = 0.6;
const _tail = 10.0;
const _gap = 6.0;
const _padding = EdgeInsets.symmetric(horizontal: 12, vertical: 6);

TextStyle bubbleTextStyle(Color ink) => TypeTokens.body.copyWith(color: ink);

typedef _Said = ({BubbleView bubble, String seatId});

/// A bubble placed in the scene.
@immutable
final class BubblePlacement {
  const BubblePlacement({required this.rect, required this.tailX});

  final Rect rect;

  /// The tail's x, toward the speaker, in scene coordinates.
  final double tailX;
}

/// Places bubbles of [sizes] over [anchors] (contracts/scene-layout.md
/// "Bubbles"): above the head, inside the margins, the second moved up or
/// across so the two never overlap.
List<BubblePlacement> placeBubbles(
  List<Size> sizes,
  List<Offset> anchors, {
  required Size scene,
}) {
  final placed = <BubblePlacement>[];
  for (final (i, size) in sizes.indexed) {
    final anchor = anchors[i];
    double left(double x) => x.clamp(
      bubbleMargin,
      max(bubbleMargin, scene.width - bubbleMargin - size.width),
    );
    double top(double y) => max(bubbleMargin, y);
    var rect = Rect.fromLTWH(
      left(anchor.dx - size.width / 2),
      top(anchor.dy - _tail - size.height),
      size.width,
      size.height,
    );
    for (final other in placed) {
      if (!rect.overlaps(other.rect.inflate(_gap / 2))) continue;
      final above = other.rect.top - _gap - size.height;
      if (above >= bubbleMargin) {
        rect = Rect.fromLTWH(rect.left, above, size.width, size.height);
        continue;
      }
      // No room above: beside the other one.
      final right = other.rect.right + _gap;
      final leftSide = other.rect.left - _gap - size.width;
      final x = right + size.width <= scene.width - bubbleMargin
          ? right
          : max(bubbleMargin, leftSide);
      rect = Rect.fromLTWH(x, rect.top, size.width, size.height);
    }
    placed.add(
      BubblePlacement(
        rect: rect,
        tailX: anchor.dx.clamp(
          rect.left + 14,
          max(rect.left + 14, rect.right - 14),
        ),
      ),
    );
  }
  return placed;
}

class BubblesLayer extends StatelessWidget {
  const BubblesLayer({required this.layout, super.key});

  final SceneLayout layout;

  @override
  Widget build(BuildContext context) {
    return MediaQuery.withNoTextScaling(
      child: TripSelector<List<_Said>>(
        select: (model) {
          final view = model.view;
          if (view == null) return const [];
          return [
            for (final b in view.bubbles)
              if (view.passenger(b.passengerId)?.seatId case final seat?)
                (bubble: b, seatId: seat),
          ];
        },
        equals: listEquals,
        builder: (context, said) => _Bubbles(layout: layout, said: said),
      ),
    );
  }
}

class _Bubbles extends StatelessWidget {
  const _Bubbles({required this.layout, required this.said});

  final SceneLayout layout;
  final List<_Said> said;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final direction = Directionality.of(context);
    // Measured as the bubble's Text draws: over the inherited style, which
    // brings the theme's spacing and line height.
    final inherited = DefaultTextStyle.of(context);
    final style = inherited.style.merge(bubbleTextStyle(tokens.hibr));
    final locale = Localizations.maybeLocaleOf(context);
    final maxText =
        layout.width * bubbleMaxShare -
        _padding.horizontal -
        2 * ShapeTokens.borderCard;
    final shown = <_Said>[];
    final sizes = <Size>[];
    final anchors = <Offset>[];
    for (final s in said) {
      final seat = layout.seats[s.seatId];
      if (seat == null) continue;
      final painter = TextPainter(
        text: TextSpan(text: s.bubble.text, style: style),
        textDirection: direction,
        textScaler: TextScaler.noScaling,
        textHeightBehavior: inherited.textHeightBehavior,
        locale: locale,
      )..layout(maxWidth: maxText);
      // Rounded up: a fraction less and the Text wraps a line the bubble
      // has no room for.
      sizes.add(
        Size(
          painter.width.ceilToDouble() +
              _padding.horizontal +
              2 * ShapeTokens.borderCard,
          painter.height.ceilToDouble() +
              _padding.vertical +
              2 * ShapeTokens.borderCard,
        ),
      );
      painter.dispose();
      anchors.add(Offset(seat.bubbleAnchor.x, seat.bubbleAnchor.y));
      shown.add(s);
    }
    final placements = placeBubbles(
      sizes,
      anchors,
      scene: Size(layout.width, layout.height),
    );
    return Stack(
      children: [
        for (final (i, s) in shown.indexed)
          Positioned.fromRect(
            rect: placements[i].rect,
            child: Bubble(
              key: ValueKey(
                'bubble-${s.bubble.passengerId}-${s.bubble.shownAtMs}',
              ),
              text: s.bubble.text,
              style: s.bubble.style,
              tailX: placements[i].tailX - placements[i].rect.left,
              tailDown: anchors[i].dy > placements[i].rect.bottom,
            ),
          ),
      ],
    );
  }
}

/// One speech bubble, in its style's color, with a hard shadow.
class Bubble extends StatelessWidget {
  const Bubble({
    required this.text,
    required this.style,
    required this.tailX,
    required this.tailDown,
    super.key,
  });

  final String text;
  final BubbleStyle style;

  /// From the bubble's left edge.
  final double tailX;

  /// Whether the speaker is below (the tail shows).
  final bool tailDown;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final fill = switch (style) {
      BubbleStyle.plain => tokens.waraq,
      BubbleStyle.warning => tokens.bubbleWarn,
      BubbleStyle.fight => tokens.bubbleFight,
      BubbleStyle.thanks => tokens.bubbleThanks,
    };
    final body = CustomPaint(
      painter: _BubblePainter(
        fill: fill,
        ink: tokens.hibr,
        tailX: tailX,
        tailDown: tailDown,
        shadow: hardShadowOffset(3, Directionality.of(context)),
      ),
      child: Padding(
        padding: _padding + const EdgeInsets.all(ShapeTokens.borderCard),
        child: Text(text, style: bubbleTextStyle(tokens.hibr)),
      ),
    );
    if (MediaQuery.disableAnimationsOf(context)) return body;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.8, end: 1),
      duration: TripMotion.bubblePop,
      curve: Curves.easeOutBack,
      builder: (context, scale, child) => Transform.scale(
        scale: scale,
        alignment: Alignment.bottomCenter,
        child: child,
      ),
      child: body,
    );
  }
}

class _BubblePainter extends CustomPainter {
  const _BubblePainter({
    required this.fill,
    required this.ink,
    required this.tailX,
    required this.tailDown,
    required this.shadow,
  });

  final Color fill;
  final Color ink;
  final double tailX;
  final bool tailDown;
  final Offset shadow;

  Path _shape(Size size) {
    final body = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(ShapeTokens.radiusControl),
    );
    final path = Path()..addRRect(body);
    if (tailDown) {
      path
        ..moveTo(tailX - 7, size.height - 1)
        ..lineTo(tailX, size.height + _tail - 2)
        ..lineTo(tailX + 7, size.height - 1)
        ..close();
    }
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final shape = _shape(size);
    canvas
      ..drawPath(shape.shift(shadow), Paint()..color = ink)
      ..drawPath(shape, Paint()..color = fill)
      ..drawPath(
        shape,
        Paint()
          ..color = ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = ShapeTokens.borderCard
          ..strokeJoin = StrokeJoin.round,
      );
  }

  @override
  bool shouldRepaint(_BubblePainter old) =>
      old.fill != fill ||
      old.ink != ink ||
      old.tailX != tailX ||
      old.tailDown != tailDown ||
      old.shadow != shadow;
}
