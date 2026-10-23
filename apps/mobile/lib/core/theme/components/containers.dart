import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/components/app_icon.dart';
import 'package:wassal/core/theme/components/buttons.dart';
import 'package:wassal/core/theme/components/pressable.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

/// The bus icon's rounded nose and window corners, in its view box.
const _iconNose = 2.0;
const _iconWindow = 1.0;

/// Containers (HANDOFF §3.3).

/// The top inset every screen keeps: the phone's status bar, but never less
/// than 24 (HANDOFF §2.4; spec FR-018). The design's fixed 36 stands for it.
double screenTopInset(BuildContext context) =>
    math.max(MediaQuery.viewPaddingOf(context).top, DesignExtras.minTopInset);

/// A white card with the card lip. [locked]: `locked.bg`, a 2 pt `outline`
/// ring inside, `ink.2` text and a lock at the top-end corner, never faded
/// (spec FR-012).
class AppCard extends StatelessWidget {
  const AppCard({
    required this.child,
    this.locked = false,
    this.padding = const EdgeInsets.all(SpaceTokens.s16),
    super.key,
  });

  final Widget child;
  final bool locked;
  final EdgeInsetsGeometry padding;

  static const double _lock = 18;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(RadiusTokens.card);
    final card = DecoratedBox(
      decoration: BoxDecoration(
        color: locked ? ColorTokens.lockedBg : ColorTokens.paper,
        borderRadius: radius,
        border: locked
            ? Border.all(
                color: RingTokens.locked.color,
                width: RingTokens.locked.width,
                strokeAlign: BorderSide.strokeAlignInside,
              )
            : null,
        boxShadow: locked ? null : const [LipTokens.card],
      ),
      child: Padding(padding: padding, child: child),
    );
    if (!locked) return card;
    return DefaultTextStyle.merge(
      style: const TextStyle(color: ColorTokens.ink2),
      child: Stack(
        children: [
          card,
          const PositionedDirectional(
            top: SpaceTokens.s12,
            end: SpaceTokens.s12,
            child: AppIcon('lock', size: _lock, color: ColorTokens.iconOff),
          ),
        ],
      ),
    );
  }
}

/// A row in a list: a `row` title, an optional caption, and a trailing
/// chevron, switch or price. Tappable when [onTap] is set.
class ListRow extends StatelessWidget {
  const ListRow({
    required this.title,
    this.caption,
    this.trailing,
    this.onTap,
    this.semanticLabel,
    super.key,
  });

  final String title;
  final String? caption;
  final Widget? trailing;
  final VoidCallback? onTap;
  final String? semanticLabel;

  static const double minHeight = 52;
  static const double _padding = 14;

  @override
  Widget build(BuildContext context) {
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: minHeight),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: _padding,
          vertical: SpaceTokens.s8,
        ),
        child: Row(
          spacing: SpaceTokens.s12,
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TypeTokens.row.copyWith(color: ColorTokens.ink),
                  ),
                  if (caption case final caption?)
                    Text(
                      caption,
                      style: TypeTokens.caption.copyWith(
                        color: ColorTokens.inkMuted,
                      ),
                    ),
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
    if (onTap == null) return row;
    return Pressable(onTap: onTap, semanticLabel: semanticLabel, child: row);
  }
}

/// A row's "go on" mark: the `back` chevron mirrored, so it points to the
/// end side (left in RTL).
class ListRowChevron extends StatelessWidget {
  const ListRowChevron({super.key});

  static const double _size = 20;

  @override
  Widget build(BuildContext context) => Transform.flip(
    flipX: true,
    child: const AppIcon('back', size: _size, color: ColorTokens.iconOff),
  );
}

/// A bar's fill: `primary` (trips, tasks), `gold` (savings), `sun` (events).
enum ProgressColor { primary, gold, sun }

/// A progress bar: a `track` with a fill that tweens its width over 500 ms
/// on each change, and jumps under reduced motion.
class ProgressBar extends StatelessWidget {
  const ProgressBar({
    required this.value,
    this.color = ProgressColor.primary,
    this.height = defaultHeight,
    super.key,
  }) : semanticLabel = null,
       _road = false;

  /// The loading screen's road (HANDOFF `Loading` block 4): a `scene.road`
  /// pill on a `sun.lip` lip with a dashed lane, and a microbus marker that
  /// travels right to left to [value]. Each update moves it linearly over
  /// at most 150 ms, and jumps under reduced motion. A screen reader hears
  /// [semanticLabel] and the percent.
  const ProgressBar.road({required this.value, this.semanticLabel, super.key})
    : color = ProgressColor.primary,
      height = roadHeight,
      _road = true;

  /// From 0 to 1.
  final double value;
  final ProgressColor color;

  /// 8 to 12 (HANDOFF §3.3).
  final double height;

  /// The road's name for a screen reader.
  final String? semanticLabel;
  final bool _road;

  static const double defaultHeight = 10;
  static const fillKey = Key('ProgressBar.fill');

  static const double roadHeight = 24;
  static const Size roadMarker = Size(44, 30);
  static const roadMarkerKey = Key('ProgressBar.roadMarker');

  @override
  Widget build(BuildContext context) {
    if (_road) return _RoadBar(value: value, semanticLabel: semanticLabel);
    final fill = switch (color) {
      ProgressColor.primary => ColorTokens.primary,
      ProgressColor.gold => ColorTokens.gold,
      ProgressColor.sun => ColorTokens.sun,
    };
    final radius = BorderRadius.circular(RadiusTokens.pill);
    return Container(
      height: height,
      decoration: BoxDecoration(color: ColorTokens.track, borderRadius: radius),
      alignment: AlignmentDirectional.centerStart,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: value.clamp(0, 1)),
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : DesignExtras.progressTween,
        curve: DesignExtras.progressCurve,
        builder: (context, v, _) => FractionallySizedBox(
          key: fillKey,
          widthFactor: v,
          heightFactor: 1,
          child: DecoratedBox(
            decoration: BoxDecoration(color: fill, borderRadius: radius),
          ),
        ),
      ),
    );
  }
}

class _RoadBar extends StatelessWidget {
  const _RoadBar({required this.value, required this.semanticLabel});

  final double value;
  final String? semanticLabel;

  /// The marker rises this far above the road.
  static const double _markerRise = 10;
  static const double _markerRadius = 12;
  static const Size _glyph = Size(26, 18);

  /// The lane: inset 14, 10 from the top, 4 high.
  static const double _laneInset = 14;
  static const double _laneTop = 10;
  static const double _laneHeight = 4;

  @override
  Widget build(BuildContext context) {
    final target = value.clamp(0.0, 1.0);
    return Semantics(
      label: semanticLabel,
      value: '${(target * 100).round()}%',
      child: SizedBox(
        height: ProgressBar.roadHeight,
        child: LayoutBuilder(
          builder: (context, constraints) => TweenAnimationBuilder<double>(
            tween: Tween(end: target),
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : DesignExtras.roadStep,
            curve: DesignExtras.roadStepCurve,
            builder: (context, v, _) => Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: ColorTokens.sceneRoad,
                      borderRadius: BorderRadius.circular(RadiusTokens.pill),
                      boxShadow: const [LipTokens.sun],
                    ),
                  ),
                ),
                const Positioned(
                  left: _laneInset,
                  right: _laneInset,
                  top: _laneTop,
                  height: _laneHeight,
                  child: CustomPaint(painter: _LanePainter()),
                ),
                // Physical right to left: the bar is a road, not text.
                Positioned(
                  key: ProgressBar.roadMarkerKey,
                  left:
                      (1 - v) * constraints.maxWidth -
                      ProgressBar.roadMarker.width / 2,
                  top: -_markerRise,
                  width: ProgressBar.roadMarker.width,
                  height: ProgressBar.roadMarker.height,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: ColorTokens.primary,
                      borderRadius: BorderRadius.circular(_markerRadius),
                      boxShadow: const [DesignExtras.roadMarkerLip],
                    ),
                    child: const Center(
                      child: CustomPaint(
                        size: _glyph,
                        painter: _MicrobusGlyphPainter(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The road's lane line: `paper` at 80%, 14 on and 12 off from the left.
class _LanePainter extends CustomPainter {
  const _LanePainter();

  static const double _dash = 14;
  static const double _gap = 12;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = ColorTokens.paper.withValues(alpha: 0.8);
    for (var x = 0.0; x < size.width; x += _dash + _gap) {
      canvas.drawRect(
        Rect.fromLTWH(x, 0, math.min(_dash, size.width - x), size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_LanePainter oldDelegate) => false;
}

/// The marker's white microbus, facing left (the `Loading` HTML's 32×24
/// glyph drawn at 26×18).
class _MicrobusGlyphPainter extends CustomPainter {
  const _MicrobusGlyphPainter();

  static const Size _viewBox = Size(32, 24);

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..scale(size.width / _viewBox.width, size.height / _viewBox.height);
    final body = Path()
      ..moveTo(3, 17)
      ..lineTo(3, 9)
      ..quadraticBezierTo(4, 5, 8, 4)
      ..lineTo(27, 4)
      ..arcToPoint(
        const Offset(29, 6),
        radius: const Radius.circular(_iconNose),
      )
      ..lineTo(29, 17)
      ..close();
    canvas.drawPath(body, Paint()..color = ColorTokens.paper);
    final window = Paint()..color = ColorTokens.sceneWindow;
    for (final x in const [8.0, 17.0]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, 6.5, 6, 4.5),
          const Radius.circular(_iconWindow),
        ),
        window,
      );
    }
    final wheel = Paint()..color = ColorTokens.sun;
    for (final x in const [9.0, 24.0]) {
      canvas.drawCircle(Offset(x, 18), 3, wheel);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MicrobusGlyphPainter oldDelegate) => false;
}

/// A screen's header, 52 high under the top inset: the back control at the
/// start side (right in RTL), the title in `display.l`, and optional pills
/// at the end.
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({
    required this.title,
    this.onBack,
    this.trailing = const [],
    super.key,
  });

  final String title;

  /// Null on a tab's root, which has no back control.
  final VoidCallback? onBack;
  final List<Widget> trailing;

  static const double height = 52;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(top: screenTopInset(context)),
    child: SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: LayoutTokens.gutter),
        child: Row(
          spacing: SpaceTokens.s12,
          children: [
            if (onBack case final onBack?)
              IconCircleButton(
                icon: 'back',
                semanticLabel: AppLocalizations.of(context).backLabel,
                onTap: onBack,
              ),
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: TypeTokens.displayL.copyWith(color: ColorTokens.ink),
                ),
              ),
            ),
            ...trailing,
          ],
        ),
      ),
    ),
  );
}

/// Nothing to show yet: an optional picture and a centred message.
class EmptyState extends StatelessWidget {
  const EmptyState({required this.message, this.picture, super.key});

  final String message;
  final Widget? picture;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(LayoutTokens.gutter),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      spacing: SpaceTokens.s12,
      children: [
        ?picture,
        Text(
          message,
          textAlign: TextAlign.center,
          style: TypeTokens.body.copyWith(color: ColorTokens.inkMuted),
        ),
      ],
    ),
  );
}
