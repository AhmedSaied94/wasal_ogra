import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/art/rive_art.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';

/// Story pieces (HANDOFF §3.3): the comic panel, the coach mark and the
/// loader.

/// One panel of a comic (`Intro` boxes 3–9): the art on `scene.sky` in a
/// radius-26 card with the dark lip, a `sun` caption at the top-end corner
/// and the speaker's line in a white bubble at the start side.
class ComicPanel extends StatelessWidget {
  const ComicPanel({
    required this.art,
    this.caption,
    this.speaker,
    this.line,
    super.key,
  });

  final Widget art;
  final String? caption;
  final String? speaker;
  final String? line;

  static const double _inset = 14;
  static const double _bubbleTop = 76;
  static const double _bubbleWidth = 236;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(RadiusTokens.scene);
    final caption = this.caption;
    final line = this.line;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: ColorTokens.sceneSky,
        borderRadius: radius,
        boxShadow: const [LipTokens.dark],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            art,
            if (caption != null)
              PositionedDirectional(
                top: _inset,
                end: _inset,
                child: _Caption(caption),
              ),
            if (line != null)
              PositionedDirectional(
                top: _bubbleTop,
                start: _inset,
                width: _bubbleWidth,
                child: _ComicBubble(speaker: speaker, line: line),
              ),
          ],
        ),
      ),
    );
  }
}

class _Caption extends StatelessWidget {
  const _Caption(this.text);

  final String text;

  static const double _radius = 12;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
    decoration: BoxDecoration(
      color: ColorTokens.sun,
      borderRadius: BorderRadius.circular(_radius),
      boxShadow: const [LipTokens.sunS],
    ),
    child: Text(
      text,
      style: TypeTokens.caption.weight(700).copyWith(color: ColorTokens.ink),
    ),
  );
}

class _ComicBubble extends StatelessWidget {
  const _ComicBubble({required this.speaker, required this.line});

  final String? speaker;
  final String line;

  static const double _radius = 20;
  static const double _tail = 16;
  static const double _tailStart = 64;

  @override
  Widget build(BuildContext context) {
    final speaker = this.speaker;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        PositionedDirectional(
          bottom: -_tail / 2,
          start: _tailStart,
          child: Transform.rotate(
            angle: math.pi / 4,
            child: Container(
              width: _tail,
              height: _tail,
              decoration: const BoxDecoration(
                color: ColorTokens.paper,
                borderRadius: BorderRadius.only(
                  bottomRight: Radius.circular(RadiusTokens.xs),
                ),
              ),
            ),
          ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          decoration: BoxDecoration(
            color: ColorTokens.paper,
            borderRadius: BorderRadius.circular(_radius),
            boxShadow: const [LipTokens.bubble],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (speaker != null)
                Text(
                  speaker,
                  style: TypeTokens.label.copyWith(color: ColorTokens.inkMuted),
                ),
              Text(
                line,
                style: DesignExtras.comicLine.copyWith(color: ColorTokens.ink),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A coach mark (`Tutorial`, HANDOFF §3.3): the `scrim.coach` over
/// everything but a radius-18 hole around [target] (6 points out), a 4 pt
/// `sun` ring on the hole's edge and a pointing hand. Only the target, seen
/// through the hole, takes a tap; the scrim absorbs every other one.
///
/// Lay it over the screen in a [Stack], in the screen's coordinates.
/// [children] (Belya's bubble) go above the scrim.
class CoachMark extends StatefulWidget {
  const CoachMark({
    required this.target,
    this.children = const [],
    this.showHand = true,
    super.key,
  });

  /// The one tappable target, in this widget's coordinates.
  final Rect target;
  final List<Widget> children;
  final bool showHand;

  static const double holePadding = 6;
  static const double holeRadius = 18;
  static const double ringWidth = 4;

  static const double _handTravel = 6;
  static const _handLoop = Duration(milliseconds: 900);

  Rect get hole => target.inflate(holePadding);

  @override
  State<CoachMark> createState() => _CoachMarkState();
}

class _CoachMarkState extends State<CoachMark>
    with SingleTickerProviderStateMixin {
  late final _tap = AnimationController(
    vsync: this,
    duration: CoachMark._handLoop,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) || !widget.showHand) {
      _tap
        ..stop()
        ..value = 0;
    } else if (!_tap.isAnimating) {
      unawaited(_tap.repeat(reverse: true));
    }
  }

  @override
  void dispose() {
    _tap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final target = widget.target;
    return Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(painter: _CoachScrim(widget.hole)),
        if (widget.showHand)
          Positioned(
            left: CoachHand.placeFor(target).dx,
            top: CoachHand.placeFor(target).dy,
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _tap,
                builder: (context, child) => Transform.translate(
                  offset: Offset(0, -CoachMark._handTravel * _tap.value),
                  child: child,
                ),
                child: const CoachHand(),
              ),
            ),
          ),
        ...widget.children,
      ],
    );
  }
}

/// The pointing hand (`Tutorial` box 58, `Components`): a white glove with
/// an ink outline, 56×64, its fingertip at the top.
class CoachHand extends StatelessWidget {
  const CoachHand({super.key}) : _down = false;

  static const size = Size(56, 64);

  /// Its top-left against what it points at: the fingertip just inside the
  /// target's bottom edge, a little past its middle (`Tutorial`: the hand at
  /// (230, 690) under the cell at (198, 648) 87×44).
  static Offset placeFor(Rect target) =>
      Offset(target.center.dx - _tipFromLeft, target.bottom - _tipInside);

  /// The same from above, for a [CoachHand.down]: the fingertip just inside
  /// the target's top edge.
  static Offset placeAbove(Rect target) => Offset(
    target.center.dx - _tipFromLeft,
    target.top + _tipInside - size.height,
  );

  /// Pointing down: the glove flipped, its fingertip at the bottom.
  const CoachHand.down({super.key}) : _down = true;

  final bool _down;

  static const double _tipFromLeft = 11.5;
  static const double _tipInside = 2;

  @override
  Widget build(BuildContext context) {
    // `wassal.riv`'s tapping hand, fitted into the glove's box; the glove
    // without the file and under reduced motion.
    final hand = SizedBox.fromSize(
      size: size,
      child: const RiveArtView(
        artboard: 'CoachHand',
        fallback: CustomPaint(size: size, painter: _GlovePainter()),
      ),
    );
    return _down ? Transform.flip(flipY: true, child: hand) : hand;
  }
}

/// `Tutorial`'s glove, on its 56×64 grid.
class _GlovePainter extends CustomPainter {
  /// The glove's rounded fingertip and thumb, knuckle, and heel.
  static const double _tip = 5;
  static const double _knuckle = 7;
  static const double _heel = 9;

  const _GlovePainter();

  static const double _outline = 3;

  static final _glove = Path()
    ..moveTo(22, 4)
    ..relativeArcToPoint(
      const Offset(10, 0),
      radius: const Radius.circular(_tip),
    )
    ..lineTo(32, 26)
    ..relativeLineTo(12, 2)
    ..relativeArcToPoint(
      const Offset(6, 8),
      radius: const Radius.circular(_knuckle),
    )
    ..relativeLineTo(-3, 16)
    ..relativeArcToPoint(
      const Offset(-9, 8),
      radius: const Radius.circular(_heel),
    )
    ..lineTo(24, 60)
    ..relativeArcToPoint(
      const Offset(-7, -4),
      radius: const Radius.circular(_heel),
    )
    ..lineTo(5, 38)
    ..relativeArcToPoint(
      const Offset(8, -6),
      radius: const Radius.circular(_tip),
    )
    ..relativeLineTo(9, 8)
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..drawPath(_glove, Paint()..color = ColorTokens.paper)
      ..drawPath(
        _glove,
        Paint()
          ..color = ColorTokens.ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = _outline
          ..strokeJoin = StrokeJoin.round,
      );
  }

  @override
  bool shouldRepaint(_GlovePainter oldDelegate) => false;
}

/// Paints the scrim with its hole and ring, and lets taps through the hole.
class _CoachScrim extends CustomPainter {
  const _CoachScrim(this.hole);

  final Rect hole;

  RRect get _rrect => RRect.fromRectAndRadius(
    hole,
    const Radius.circular(CoachMark.holeRadius),
  );

  @override
  void paint(Canvas canvas, Size size) {
    final scrim = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(_rrect);
    canvas
      ..drawPath(scrim, Paint()..color = ColorTokens.scrimCoach)
      ..drawRRect(
        _rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = CoachMark.ringWidth
          ..color = ColorTokens.sun,
      );
  }

  /// Outside the hole the scrim is hit, and so absorbs the tap; inside it is
  /// not, so the tap reaches the target below.
  @override
  bool hitTest(Offset position) => !_rrect.contains(position);

  @override
  bool shouldRepaint(_CoachScrim old) => old.hole != hole;
}

/// «Loading» (`States` boxes 39–42): a `primary` marker with its lip
/// driving along a 200×16 `scene.road`, right to left, over the label.
/// Under reduced motion the marker stands where the artboard puts it.
class MicrobusLoader extends StatefulWidget {
  const MicrobusLoader({required this.label, super.key});

  final String label;

  static const roadKey = Key('MicrobusLoader.road');
  static const markerKey = Key('MicrobusLoader.marker');
  static const Size road = Size(200, 16);
  static const Size marker = Size(36, 24);
  static const double height = 64;

  static const double _markerRadius = 10;

  /// The artboard's marker, 40% of the road from its start.
  static const double _still = 0.4;
  static const _lap = Duration(milliseconds: 1400);

  @override
  State<MicrobusLoader> createState() => _MicrobusLoaderState();
}

class _MicrobusLoaderState extends State<MicrobusLoader>
    with SingleTickerProviderStateMixin {
  late final _drive = AnimationController(
    vsync: this,
    duration: MicrobusLoader._lap,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _drive
        ..stop()
        ..value = MicrobusLoader._still;
    } else if (!_drive.isAnimating) {
      unawaited(_drive.repeat());
    }
  }

  @override
  void dispose() {
    _drive.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const road = MicrobusLoader.road;
    const marker = MicrobusLoader.marker;
    // `wassal.riv`'s spinning wheel rolls along the road; without the file
    // and under reduced motion, the board's marker.
    final car = SizedBox.fromSize(
      size: marker,
      child: RiveArtView(
        artboard: 'LoadingWheel',
        fallback: Container(
          key: MicrobusLoader.markerKey,
          decoration: BoxDecoration(
            color: ColorTokens.primary,
            borderRadius: BorderRadius.circular(MicrobusLoader._markerRadius),
            boxShadow: const [DesignExtras.roadMarkerLip],
          ),
        ),
      ),
    );
    return Semantics(
      label: widget.label,
      child: SizedBox(
        height: MicrobusLoader.height,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: SpaceTokens.s8,
          children: [
            SizedBox.fromSize(
              key: MicrobusLoader.roadKey,
              size: road,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: ColorTokens.sceneRoad,
                        borderRadius: BorderRadius.circular(RadiusTokens.pill),
                      ),
                    ),
                  ),
                  AnimatedBuilder(
                    animation: _drive,
                    builder: (context, _) => PositionedDirectional(
                      top: (road.height - marker.height) / 2 - SpaceTokens.s4,
                      start: (road.width - marker.width) * _drive.value,
                      child: car,
                    ),
                  ),
                ],
              ),
            ),
            ExcludeSemantics(
              child: Text(
                widget.label,
                style: TypeTokens.caption
                    .weight(600)
                    .copyWith(color: ColorTokens.ink2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
