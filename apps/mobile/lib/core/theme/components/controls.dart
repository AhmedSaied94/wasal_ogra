import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/components/pressable.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';

/// Controls (HANDOFF §3.3, `Components` boxes 50–61).

/// An on/off switch in its own row: the label and the 52×30 track. A tap
/// anywhere on the row toggles. On: `primary`, the knob at the end side
/// (left in RTL). Off: `ground.lip`, the knob at the start. [framed] puts
/// the row on a white card (as in `Components`); without it the row is
/// bare (as in `Pause`).
class AppSwitch extends StatelessWidget {
  const AppSwitch({
    required this.label,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.framed = true,
    super.key,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;
  final bool framed;

  static const trackKey = Key('AppSwitch.track');
  static const knobKey = Key('AppSwitch.knob');

  static const Size track = Size(52, 30);
  static const double _knob = 24;
  static const double _inset = 3;
  static const double rowHeight = 52;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final duration = reduced ? Duration.zero : DesignExtras.switchKnob;
    final row = Container(
      height: rowHeight,
      padding: framed
          ? const EdgeInsets.symmetric(horizontal: SpaceTokens.s12)
          : EdgeInsets.zero,
      decoration: framed
          ? BoxDecoration(
              color: ColorTokens.paper,
              borderRadius: BorderRadius.circular(RadiusTokens.m),
            )
          : null,
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          mainAxisSize: constraints.hasBoundedWidth
              ? MainAxisSize.max
              : MainAxisSize.min,
          spacing: SpaceTokens.s8,
          children: [
            // Beside a ListRow's title the row is unbounded: the label then
            // takes only its own width.
            if (constraints.hasBoundedWidth)
              Expanded(child: _label())
            else
              _label(),
            AnimatedContainer(
              key: trackKey,
              duration: duration,
              width: track.width,
              height: track.height,
              padding: const EdgeInsets.all(_inset),
              decoration: BoxDecoration(
                color: value ? ColorTokens.primary : ColorTokens.groundLip,
                borderRadius: BorderRadius.circular(RadiusTokens.pill),
              ),
              child: AnimatedAlign(
                duration: duration,
                alignment: value
                    ? AlignmentDirectional.centerEnd
                    : AlignmentDirectional.centerStart,
                child: Container(
                  key: knobKey,
                  width: _knob,
                  height: _knob,
                  decoration: const BoxDecoration(
                    color: ColorTokens.paper,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return Pressable(
      onTap: () => onChanged(!value),
      enabled: enabled,
      toggled: value,
      semanticLabel: label,
      child: row,
    );
  }

  Widget _label() => Text(
    label,
    maxLines: 2,
    style: TypeTokens.row.copyWith(color: ColorTokens.ink),
  );
}

/// How a [Segmented] marks its chosen segment: `sun` with ink (rooms in
/// Apartment) or `primary` with white (tabs, Settings options).
enum SegmentedStyle { sun, primary }

/// Two to four segments sharing a white container; one is chosen.
class Segmented<T> extends StatelessWidget {
  const Segmented({
    required this.value,
    required this.segments,
    required this.onChanged,
    this.style = SegmentedStyle.primary,
    this.segmentKey,
    super.key,
  }) : assert(segments.length >= 2 && segments.length <= 4);

  final T value;

  /// Each segment's value and label, in the HTML's order.
  final List<(T, String)> segments;
  final ValueChanged<T> onChanged;
  final SegmentedStyle style;

  /// A key for each segment's tap target, for finding one in tests.
  final Key Function(T value)? segmentKey;

  static const double _segment = 40;
  static const double _padding = SpaceTokens.s4;
  static const double _radius = RadiusTokens.tray;
  static const double _segmentRadius = RadiusTokens.s;

  @override
  Widget build(BuildContext context) {
    final (activeFill, activeInk) = switch (style) {
      SegmentedStyle.sun => (ColorTokens.sun, ColorTokens.ink),
      SegmentedStyle.primary => (ColorTokens.primary, ColorTokens.paper),
    };
    return Container(
      padding: const EdgeInsets.all(_padding),
      decoration: BoxDecoration(
        color: ColorTokens.paper,
        borderRadius: BorderRadius.circular(_radius),
      ),
      child: Row(
        spacing: SpaceTokens.s4,
        children: [
          for (final (v, label) in segments)
            Expanded(
              child: Pressable(
                key: segmentKey?.call(v),
                onTap: () => onChanged(v),
                selected: v == value,
                semanticLabel: label,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: v == value ? activeFill : null,
                    borderRadius: BorderRadius.circular(_segmentRadius),
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    height: _segment,
                    child: Center(
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: v == value
                            ? DesignExtras.segmentLabel
                                  .weight(700)
                                  .copyWith(color: activeInk)
                            : DesignExtras.segmentLabel.copyWith(
                                color: ColorTokens.ink2,
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A one-line text field: 52 high, white, a 2 pt `ground.lip` ring that
/// turns `primary` with focus.
class AppTextField extends StatefulWidget {
  const AppTextField({
    required this.controller,
    required this.semanticLabel,
    this.onChanged,
    this.maxLength,
    super.key,
  });

  final TextEditingController controller;
  final String semanticLabel;
  final ValueChanged<String>? onChanged;
  final int? maxLength;

  static const frameKey = Key('AppTextField.frame');
  static const double height = 52;
  static const double _padding = 14;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_refocused);
  }

  void _refocused() => setState(() {});

  @override
  void dispose() {
    _focus
      ..removeListener(_refocused)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ring = _focus.hasFocus
        ? RingTokens.selected.copyWithWidth(RingTokens.empty.width)
        : RingTokens.empty;
    // The whole 52-high frame focuses the field, not only its text line.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      onTap: _focus.requestFocus,
      child: _frame(context, ring),
    );
  }

  Widget _frame(BuildContext context, RingSpec ring) {
    return AnimatedContainer(
      key: AppTextField.frameKey,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : MotionTokens.press,
      height: AppTextField.height,
      padding: const EdgeInsets.symmetric(horizontal: AppTextField._padding),
      alignment: AlignmentDirectional.centerStart,
      decoration: BoxDecoration(
        color: ColorTokens.paper,
        borderRadius: BorderRadius.circular(RadiusTokens.m),
        border: Border.all(
          color: ring.color,
          width: ring.width,
          strokeAlign: BorderSide.strokeAlignInside,
        ),
      ),
      child: Semantics(
        label: widget.semanticLabel,
        // TextField needs a Material ancestor; screens have none.
        child: Material(
          type: MaterialType.transparency,
          child: TextField(
            controller: widget.controller,
            focusNode: _focus,
            onChanged: widget.onChanged,
            maxLength: widget.maxLength,
            cursorColor: ColorTokens.primary,
            style: DesignExtras.fieldText.copyWith(color: ColorTokens.ink),
            decoration: const InputDecoration.collapsed(hintText: null)
                .copyWith(counterText: ''),
          ),
        ),
      ),
    );
  }
}

extension on RingSpec {
  RingSpec copyWithWidth(double width) =>
      RingSpec(width: width, color: color, inside: inside, dashed: dashed);
}
