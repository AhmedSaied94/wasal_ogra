import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/audio_haptics/vibration_setting.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';

/// The press every «كرتون ناعم» control shares (HANDOFF §2.3;
/// specs/008.5-m21-design-refresh, contracts/components.md "Rules").
///
/// Pressing moves [child] down by its [lip]'s depth while the lip shrinks to
/// nothing, so the bottom edge stays put, as if pushed into the page, over
/// `MotionTokens.press`; releasing reverses it. A press ticks the haptic
/// unless vibration is off. Without a lip, [pressedOpacity] fades the child
/// instead (the tertiary button). Disabled: 45% opacity, no lip, no press.
///
/// The hit area is at least 44×44, centred on [child], however small it is
/// drawn. No Material ink: a [GestureDetector] does the work.
class Pressable extends ConsumerStatefulWidget {
  const Pressable({
    required this.child,
    required this.onTap,
    this.lip,
    this.borderRadius = BorderRadius.zero,
    this.pressedOpacity,
    this.enabled = true,
    this.semanticLabel,
    this.selected,
    this.toggled,
    this.haptic = true,
    this.expand = false,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;

  /// Lets [child] fill the room it is given instead of being centred at its
  /// own size, for a card that stretches to its row's height.
  final bool expand;

  /// The solid shadow under [child]; its y offset is the press depth.
  final BoxShadow? lip;

  /// The lip's shape: [child]'s corners.
  final BorderRadius borderRadius;

  /// The child's opacity while pressed, for controls without a lip.
  final double? pressedOpacity;
  final bool enabled;

  /// What a screen reader says. Without one, [child]'s text is read.
  final String? semanticLabel;

  /// For a segment: whether it is the chosen one.
  final bool? selected;

  /// For a switch: whether it is on.
  final bool? toggled;

  /// Whether a press ticks the haptic. The trip's controls leave vibrating
  /// to the trip's own cues (M02), so they turn it off.
  final bool haptic;

  /// Opacity of a disabled control (tokens.json `color_rules`).
  static const disabledOpacity = 0.45;

  /// The smallest hit area (ux-spec minimum sizes).
  static const minHit = Size(LayoutTokens.touchMin, LayoutTokens.touchMin);

  @override
  ConsumerState<Pressable> createState() => _PressableState();
}

class _PressableState extends ConsumerState<Pressable>
    with SingleTickerProviderStateMixin {
  late final _press = AnimationController(
    vsync: this,
    duration: MotionTokens.press,
  );
  late final _curve = CurvedAnimation(
    parent: _press,
    curve: MotionTokens.pressCurve,
  );

  bool get _active => widget.enabled && widget.onTap != null;

  @override
  void didUpdateWidget(Pressable old) {
    super.didUpdateWidget(old);
    if (!_active) _press.value = 0;
  }

  @override
  void dispose() {
    _curve.dispose();
    _press.dispose();
    super.dispose();
  }

  void _down(TapDownDetails _) {
    if (widget.haptic) ref.read(pressFeedbackProvider)();
    _press.forward();
  }

  void _up(TapUpDetails _) => _press.reverse();

  void _cancel() => _press.reverse();

  @override
  Widget build(BuildContext context) {
    final active = _active;
    final face = AnimatedBuilder(
      animation: _curve,
      child: widget.child,
      builder: (context, child) => _face(child!, active ? _curve.value : 0),
    );
    return Semantics(
      container: true,
      button: widget.toggled == null,
      selected: widget.selected,
      toggled: widget.toggled,
      enabled: active,
      label: widget.semanticLabel,
      onTap: active ? widget.onTap : null,
      child: ExcludeSemantics(
        excluding: widget.semanticLabel != null,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTapDown: active ? _down : null,
          onTapUp: active ? _up : null,
          onTapCancel: active ? _cancel : null,
          onTap: active ? widget.onTap : null,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: Pressable.minHit.width,
              minHeight: Pressable.minHit.height,
            ),
            child: widget.expand
                ? face
                : Center(widthFactor: 1, heightFactor: 1, child: face),
          ),
        ),
      ),
    );
  }

  Widget _face(Widget child, double t) {
    if (!widget.enabled) {
      return Opacity(opacity: Pressable.disabledOpacity, child: child);
    }
    final lip = widget.lip;
    if (lip == null) {
      final pressed = widget.pressedOpacity;
      if (pressed == null) return child;
      return Opacity(opacity: 1 - (1 - pressed) * t, child: child);
    }
    final depth = lip.offset.dy;
    final remaining = depth * (1 - t);
    return Transform.translate(
      offset: Offset(0, depth * t),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: widget.borderRadius,
          boxShadow: remaining.abs() < 0.01
              ? const []
              : [lip.copyWith(offset: Offset(lip.offset.dx, remaining))],
        ),
        child: child,
      ),
    );
  }
}
