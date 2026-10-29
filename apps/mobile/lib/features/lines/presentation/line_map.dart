// The line map (specs/014-m09-lines-vehicles, contracts/lines.md "Layout",
// research R3, HANDOFF `Lines` block 3): the cards bottom-up on a dashed
// road, the first line at the bottom, read top to bottom. It scrolls when
// the lines don't fit, and opens with the focus line in view.
import 'package:content_models/content_models.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/components/app_icon.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/lines/domain/line_standing.dart';

class LineMap extends StatefulWidget {
  const LineMap({
    required this.cards,
    required this.focus,
    required this.cardOf,
    super.key,
  });

  /// In pack order.
  final List<LineStanding> cards;
  final LineId? focus;
  final Widget Function(LineStanding standing) cardOf;

  static const scrollKey = Key('LineMap.scroll');

  /// The road's centre from the start edge (x 356–362 in the board).
  static const double roadCentre = 31;

  /// The cards' start edge, past the road and its nodes.
  static const double cardStart = 50;
  static const double gap = SpaceTokens.s12;

  /// The road's ends stop short of the map's (HANDOFF: inset 20).
  static const double roadInset = 20;

  /// The first line's card sits this far above the bottom bar (`Lines`
  /// box 52 and the nav: 712 to 756).
  static const double bottomGap = 44;

  @override
  State<LineMap> createState() => _LineMapState();
}

class _LineMapState extends State<LineMap> {
  final _keys = <LineId, GlobalKey>{};

  GlobalKey _keyOf(LineId line) =>
      _keys.putIfAbsent(line, () => GlobalKey(debugLabel: line.name));

  @override
  void initState() {
    super.initState();
    // The focus card in view on the first frame, without animation.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final focus = widget.focus;
      final target = focus == null ? null : _keys[focus]?.currentContext;
      if (!mounted || target == null) return;
      Scrollable.ensureVisible(target, alignment: 0.5);
    });
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => SingleChildScrollView(
      key: LineMap.scrollKey,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: box.maxHeight),
        child: CustomPaint(
          painter: RoadPainter(textDirection: Directionality.of(context)),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              0,
              0,
              LayoutTokens.gutter,
              LineMap.bottomGap,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: LineMap.gap,
              children: [
                for (final standing in widget.cards.reversed)
                  Row(
                    key: _keyOf(standing.line),
                    children: [
                      SizedBox(
                        width: LineMap.cardStart,
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: _Node(state: standing.state),
                        ),
                      ),
                      Expanded(child: widget.cardOf(standing)),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// A card's stop on the road: current 32 `sun` with the route glyph, done
/// 24 with a tick, locked 24 with a ring.
class _Node extends StatelessWidget {
  const _Node({required this.state});

  final LineState state;

  static const double _big = 32;
  static const double _small = 24;
  static const double _glyph = 18;
  static const double _tick = 14;
  static const double _lockedRing = 3;

  @override
  Widget build(BuildContext context) {
    final size = state is LineCurrent ? _big : _small;
    final child = switch (state) {
      LineCurrent() => Container(
        width: _big,
        height: _big,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: ColorTokens.sun,
          borderRadius: BorderRadius.circular(RadiusTokens.s),
          boxShadow: const [LipTokens.sunS],
        ),
        child: const AppIcon(
          'route_bold',
          size: _glyph,
          color: ColorTokens.ink,
        ),
      ),
      LineDone() => Container(
        width: _small,
        height: _small,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: ColorTokens.primary,
          shape: BoxShape.circle,
        ),
        child: const AppIcon('check', size: _tick, color: ColorTokens.paper),
      ),
      LineLocked() => Container(
        width: _small,
        height: _small,
        decoration: BoxDecoration(
          color: ColorTokens.ground,
          shape: BoxShape.circle,
          border: Border.all(
            color: ColorTokens.iconOff,
            width: _lockedRing,
            strokeAlign: BorderSide.strokeAlignInside,
          ),
        ),
      ),
    };
    return Padding(
      padding: EdgeInsetsDirectional.only(start: LineMap.roadCentre - size / 2),
      child: ExcludeSemantics(child: child),
    );
  }
}

/// The dashed road: 6 wide, 10 on and 8 off, `icon.off`, from 20 below the
/// map's top to 20 above its end.
class RoadPainter extends CustomPainter {
  const RoadPainter({required this.textDirection});

  final TextDirection textDirection;

  static const double width = 6;
  static const double dashOn = 10;
  static const double dashOff = 8;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = textDirection == TextDirection.rtl
        ? size.width - LineMap.roadCentre
        : LineMap.roadCentre;
    final paint = Paint()..color = ColorTokens.iconOff;
    final end = size.height - LineMap.roadInset;
    for (var y = LineMap.roadInset; y < end; y += dashOn + dashOff) {
      canvas.drawRect(
        Rect.fromLTRB(
          centre - width / 2,
          y,
          centre + width / 2,
          (y + dashOn).clamp(y, end),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(RoadPainter old) => old.textDirection != textDirection;
}
