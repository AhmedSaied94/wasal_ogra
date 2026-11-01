// A goal's name and its figures (specs/015-m10-apartment-story, `AptGoalLine`
// and `AptGoalVehicle` block 3b): on one row, the name at the start and the
// figures at the end, when both fit; else the figures drop to a row of their
// own under the name, still at the end, so a long name («الميكروباص القديم»)
// is never cut or wrapped.
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';

class GoalHeadline extends MultiChildRenderObjectWidget {
  GoalHeadline({required Widget name, required Widget figures, super.key})
    : super(children: [name, figures]);

  /// The gap between the name's row and the figures' row, once they wrap.
  static const double wrappedGap = SpaceTokens.s2;

  /// The least gap between the two on one row.
  static const double inlineGap = SpaceTokens.s8;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderGoalHeadline(Directionality.of(context));

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderGoalHeadline).textDirection = Directionality.of(
      context,
    );
  }
}

class _ParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderGoalHeadline extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _ParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _ParentData> {
  _RenderGoalHeadline(this._textDirection);

  TextDirection _textDirection;

  set textDirection(TextDirection value) {
    if (_textDirection == value) return;
    _textDirection = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _ParentData) child.parentData = _ParentData();
  }

  RenderBox get _name => firstChild!;
  RenderBox get _figures => childAfter(_name)!;

  /// The sizes laid out under [constraints], the layout they make and the
  /// size of the whole.
  ({Size name, Size figures, bool inline, Size size}) _measure(
    BoxConstraints constraints,
    Size Function(RenderBox child, BoxConstraints c) layout,
  ) {
    final loose = BoxConstraints(maxWidth: constraints.maxWidth);
    final name = layout(_name, loose);
    final figures = layout(_figures, loose);
    final inline =
        name.width + GoalHeadline.inlineGap + figures.width <=
        constraints.maxWidth;
    final height = inline
        ? (name.height > figures.height ? name.height : figures.height)
        : name.height + GoalHeadline.wrappedGap + figures.height;
    return (
      name: name,
      figures: figures,
      inline: inline,
      size: constraints.constrain(Size(constraints.maxWidth, height)),
    );
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      _measure(constraints, (child, c) => child.getDryLayout(c)).size;

  @override
  void performLayout() {
    final m = _measure(constraints, (child, c) {
      child.layout(c, parentUsesSize: true);
      return child.size;
    });
    size = m.size;
    final rtl = _textDirection == TextDirection.rtl;
    double atStart(double w) => rtl ? size.width - w : 0;
    double atEnd(double w) => rtl ? 0 : size.width - w;
    (_name.parentData! as _ParentData).offset = Offset(
      atStart(m.name.width),
      m.inline ? (size.height - m.name.height) / 2 : 0,
    );
    (_figures.parentData! as _ParentData).offset = Offset(
      atEnd(m.figures.width),
      m.inline
          ? (size.height - m.figures.height) / 2
          : m.name.height + GoalHeadline.wrappedGap,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
