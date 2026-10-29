// The line map (specs/014-m09-lines-vehicles, contracts/lines.md "Layout",
// research R3, HANDOFF `Lines` block 3, `LinesFirst`): the cards bottom-up
// on a dashed road, the first line at the bottom, read top to bottom, and
// the road's end at the top with «خطوط جديدة جاية». It scrolls when the
// lines don't fit, and opens with the focus line in view.
import 'package:content_models/content_models.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/components/app_icon.dart';
import 'package:wassal/core/theme/components/containers.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/lines/domain/line_standing.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

class LineMap extends StatefulWidget {
  const LineMap({
    required this.cards,
    required this.focus,
    required this.cardOf,
    this.revision = 0,
    super.key,
  });

  /// In pack order.
  final List<LineStanding> cards;
  final LineId? focus;
  final Widget Function(LineStanding standing) cardOf;

  /// Bumped whenever Lines is shown again (the tab, Home's line card), so
  /// the focus scrolls back into view each time (FR-020).
  final int revision;

  static const scrollKey = Key('LineMap.scroll');

  /// The road's centre from the start edge (x 356–362 in the board).
  static const double roadCentre = 31;

  /// The cards' start edge, past the road and its nodes.
  static const double cardStart = 50;
  static const double gap = SpaceTokens.s12;

  /// The road's ends stop short of the map's (HANDOFF: inset 20).
  static const double roadInset = 20;

  /// The first line's card sits this far above the bottom bar, outside the
  /// road (`LinesFirst` box 24 and the nav: 744 to 756).
  static const double bottomGap = SpaceTokens.s12;

  /// The road's end node, this far below the map's top (`LinesFirst` box
  /// 16).
  static const double endTop = SpaceTokens.s8;

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
    WidgetsBinding.instance.addPostFrameCallback((_) => _showFocus());
  }

  @override
  void didUpdateWidget(LineMap old) {
    super.didUpdateWidget(old);
    // Lines is shown again, or the focus moved (a purchase, Home's next
    // trip): put it back in view (FR-020, US1 acceptance 6 and 7).
    if (old.focus != widget.focus || old.revision != widget.revision) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showFocus());
    }
  }

  void _showFocus() {
    final focus = widget.focus;
    final target = focus == null ? null : _keys[focus]?.currentContext;
    if (!mounted || target == null) return;
    Scrollable.ensureVisible(target, alignment: 0.5);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => SingleChildScrollView(
      key: LineMap.scrollKey,
      padding: const EdgeInsets.only(bottom: LineMap.bottomGap),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: box.maxHeight - LineMap.bottomGap,
        ),
        child: CustomPaint(
          painter: RoadPainter(textDirection: Directionality.of(context)),
          child: Padding(
            padding: const EdgeInsetsDirectional.only(end: LayoutTokens.gutter),
            // The road's end at the top, the cards at the bottom.
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _RoadEnd(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: LineMap.gap,
                  children: [
                    for (final standing in widget.cards.reversed)
                      Row(
                        key: _keyOf(standing.line),
                        children: [
                          _NodeSlot(child: _Node(state: standing.state)),
                          Expanded(child: widget.cardOf(standing)),
                        ],
                      ),
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

/// The road's end (`LinesFirst` boxes 16 and 17): an empty node and
/// «خطوط جديدة جاية» beside it, at the cards' start.
class _RoadEnd extends StatelessWidget {
  const _RoadEnd();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: LineMap.endTop),
    child: Row(
      children: [
        const _NodeSlot(child: _Node(state: null)),
        Expanded(
          child: Text(
            AppLocalizations.of(context).linesRoadEnd,
            style: DesignExtras.linesRoadEnd.copyWith(
              color: ColorTokens.inkMuted,
            ),
          ),
        ),
      ],
    ),
  );
}

/// The road's column beside a card: its node centred on the road.
class _NodeSlot extends StatelessWidget {
  const _NodeSlot({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: LineMap.cardStart,
    child: Align(alignment: AlignmentDirectional.centerStart, child: child),
  );
}

/// A card's stop on the road: current 32 `sun` with the route glyph, done
/// 24 with a tick, locked 24 with a ring; the road's end (no [state]) is
/// a ring too.
class _Node extends StatelessWidget {
  const _Node({required this.state});

  final LineState? state;

  static const double _big = 32;
  static const double _small = 24;
  static const double _tick = 12;
  static const double _lockedRing = 3;

  /// The current node's bus, as drawn (the board's 20×15).
  static const Size _bus = Size(20, 15);

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
        child: const MicrobusGlyph(
          size: _bus,
          body: ColorTokens.primary,
          // The board draws the body and wheels only.
          window: ColorTokens.primary,
          wheel: ColorTokens.ink,
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
      LineLocked() || null => Container(
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
