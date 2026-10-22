// بلية's hint (layer 8, contracts/trip-view.md "Hints"): the apprentice's
// head at the door on the scene's right, under the windows, his line in a
// bubble beside him, and a pointing hand at the passenger it is about,
// pulsing on the trip clock (steady under reduced motion). His head is a stand-in drawing
// until the art arrives.
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/app_theme.dart';
import 'package:wassal/core/theme/tokens/space.dart';
import 'package:wassal/features/trip/domain/scene_layout.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';
import 'package:wassal/features/trip/presentation/overlays/bubbles_layer.dart';
import 'package:wassal/features/trip/presentation/trip_scope.dart';
import 'package:wassal/features/trip/presentation/trip_text.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

/// بلية's head.
const balyaHeadSize = 48.0;

/// The pointing hand.
const _pointerSize = 36.0;

/// What the hint layer draws: the line, and the face it points at.
typedef _Shown = ({String text, String? seatId});

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
        );
      },
      builder: (context, shown) {
        if (shown == null) return const SizedBox.shrink();
        final top = layout.windows.height + SpaceTokens.s;
        final face = layout.seats[shown.seatId]?.face;
        return Stack(
          children: [
            if (face != null)
              Positioned(
                // On the face's top corner toward the door.
                left: face.left + face.width - _pointerSize / 2,
                top: face.top + face.height * 0.2 - _pointerSize / 2,
                child: const _Pointer(key: pointerKey),
              ),
            Positioned(
              top: top,
              right: SpaceTokens.s,
              child: Semantics(
                liveRegion: true,
                label: l10n.tripHintSemantics(shown.text),
                excludeSemantics: true,
                // Physical order: the door is on the right in either
                // direction, and بلية stands at it.
                child: Row(
                  textDirection: TextDirection.ltr,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: layout.width * 0.6),
                      child: Bubble(
                        key: bubbleKey,
                        text: shown.text,
                        style: BubbleStyle.thanks,
                        tailX: 0,
                        tailDown: false,
                      ),
                    ),
                    const SizedBox(width: SpaceTokens.xs),
                    SizedBox.square(
                      key: headKey,
                      dimension: balyaHeadSize,
                      child: CustomPaint(
                        painter: _BalyaPainter(context.tokens),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The pointing hand, pulsing on the trip clock: still while the trip is.
class _Pointer extends StatelessWidget {
  const _Pointer({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final hand = Container(
      width: _pointerSize,
      height: _pointerSize,
      decoration: BoxDecoration(
        color: tokens.gold,
        shape: BoxShape.circle,
        border: Border.all(color: tokens.hibr, width: 2),
      ),
      child: Icon(Icons.touch_app_rounded, size: 22, color: tokens.hibr),
    );
    return TripPulse(amplitude: 0.15, child: hand);
  }
}

/// بلية: a round face in a cap, smiling, in the sticker style.
class _BalyaPainter extends CustomPainter {
  const _BalyaPainter(this.tokens);

  final WassalTokens tokens;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide / 2;
    final center = size.center(Offset.zero);
    final line = math.max(2.0, r * 0.1);
    final ink = Paint()
      ..color = tokens.hibr
      ..style = PaintingStyle.stroke
      ..strokeWidth = line
      ..strokeCap = StrokeCap.round;
    canvas
      ..drawCircle(
        center + Offset(-line, line),
        r - line,
        Paint()..color = tokens.hibr,
      )
      ..drawCircle(
        center,
        r - line,
        Paint()..color = Color.lerp(tokens.gold, tokens.waraq, 0.55)!,
      )
      ..drawCircle(center, r - line, ink);
    // The cap.
    final cap = Path()
      ..addArc(
        Rect.fromCircle(center: center, radius: r - line),
        math.pi * 1.05,
        math.pi * 0.9,
      )
      ..close();
    canvas
      ..drawPath(cap, Paint()..color = tokens.primary)
      ..drawPath(cap, ink);
    // Eyes and a grin.
    final eye = Paint()..color = tokens.hibr;
    canvas
      ..drawCircle(center + Offset(-r * 0.3, r * 0.05), r * 0.08, eye)
      ..drawCircle(center + Offset(r * 0.3, r * 0.05), r * 0.08, eye)
      ..drawArc(
        Rect.fromCenter(
          center: center + Offset(0, r * 0.25),
          width: r * 0.8,
          height: r * 0.5,
        ),
        0.15 * math.pi,
        0.7 * math.pi,
        false,
        ink,
      );
  }

  @override
  bool shouldRepaint(_BalyaPainter oldDelegate) => oldDelegate.tokens != tokens;
}
