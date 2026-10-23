// A card over the darkened trip (contracts/scene-layout.md layer 9): the
// pause, the failure, a dispute, a purchase, the empty tank, a retry. Each
// is the design's `AppDialog` (HANDOFF §3.3): the smaller ones in `States`'
// spend-confirmation layout, the pause and the failure in their own
// artboards' (008.5 research R13). Only their buttons close them.
import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/components/buttons.dart';
import 'package:wassal/core/theme/components/overlays.dart';
import 'package:wassal/core/theme/components/pressable.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';

class TripCard extends StatelessWidget {
  const TripCard({
    required this.title,
    required this.children,
    this.art,
    this.titleStyle = DesignExtras.confirmTitle,
    this.scrim = ColorTokens.scrim,
    this.designTop,
    this.padding = const EdgeInsets.all(DesignExtras.dialogPadding),
    super.key,
  });

  final String title;
  final List<Widget> children;

  /// Above the title: `States`' 44 pt icon, `Pause`'s microbus, `Fail`'s
  /// faces.
  final Widget? art;
  final TextStyle titleStyle;
  final Color scrim;

  /// Where the card's top sits on the 844-high reference frame (`Pause`
  /// 170, `Fail` 120), in proportion on other screens; null centres it.
  final double? designTop;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final card = TripDialog(
      title: title,
      art: art,
      titleStyle: titleStyle,
      padding: padding,
      children: children,
    );
    // Modal: the controls under the card are gone for the screen reader
    // too, as they are for the finger. The scrim takes taps and does
    // nothing with them.
    return BlockSemantics(
      child: ColoredBox(
        color: scrim,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final insets = MediaQuery.paddingOf(context);
            const edge = SpaceTokens.s16;
            final top = switch (designTop) {
              final at? => math.max(
                at * constraints.maxHeight / LayoutTokens.frameH,
                insets.top + edge,
              ),
              null => insets.top + edge,
            };
            final bottom = insets.bottom + edge;
            return SingleChildScrollView(
              padding: EdgeInsets.only(top: top, bottom: bottom),
              child: designTop == null
                  ? ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: math.max(
                          0,
                          constraints.maxHeight - top - bottom,
                        ),
                      ),
                      child: card,
                    )
                  : card,
            );
          },
        ),
      ),
    );
  }
}

/// The card itself, without the scrim: an [AppDialog] with the picture,
/// the title and [children], 12 apart (`States` box 10).
class TripDialog extends StatelessWidget {
  const TripDialog({
    required this.title,
    required this.children,
    this.art,
    this.titleStyle = DesignExtras.confirmTitle,
    this.padding = const EdgeInsets.all(DesignExtras.dialogPadding),
    super.key,
  });

  final String title;
  final List<Widget> children;
  final Widget? art;
  final TextStyle titleStyle;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => AppDialog(
    semanticLabel: title,
    padding: padding,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: SpaceTokens.s12,
      children: [
        if (art case final art?) Center(child: art),
        Semantics(
          header: true,
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: titleStyle.copyWith(color: ColorTokens.ink),
          ),
        ),
        ...children,
      ],
    ),
  );
}

/// A line of a card's text: `caption` in `ink.muted`, centred (`States`
/// box 13).
class CardText extends StatelessWidget {
  const CardText(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    textAlign: TextAlign.center,
    style: DesignExtras.dialogSubtitle.copyWith(color: ColorTokens.inkMuted),
  );
}

/// A small line under a button (`Fail` box 18), 12 pt in `ink.muted`.
class CardNote extends StatelessWidget {
  const CardNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    textAlign: TextAlign.center,
    style: DesignExtras.dialogNote.copyWith(color: ColorTokens.inkMuted),
  );
}

/// The spend confirmation's buttons (`States` boxes 14–15): the action at
/// the start beside the way out, sharing the row two to one past the 12 pt
/// each keeps (204 and 108 on the board); or the way out alone.
class CardActions extends StatelessWidget {
  const CardActions({required this.dismiss, this.confirm, super.key});

  final Widget? confirm;
  final Widget dismiss;

  /// What each button keeps before the row is shared: a browser button's
  /// 6 pt on each side, which the board's flex measures with.
  static const _kept = 12.0;

  static List<double> _slots(double width) {
    final share = (width - SpaceTokens.s10 - 2 * _kept) / 3;
    final confirm = _kept + 2 * share;
    return [confirm, width - SpaceTokens.s10 - confirm];
  }

  @override
  Widget build(BuildContext context) {
    final confirm = this.confirm;
    if (confirm == null) return dismiss;
    return CardRow(
      slots: _slots,
      gap: SpaceTokens.s10,
      children: [confirm, dismiss],
    );
  }
}

/// Buttons side by side, each in its slot of the row (equal shares unless
/// [slots] says otherwise), while every one's label fits on its line; one
/// above another, full width and [gap] apart, when one doesn't (large
/// text, a narrow phone), so no label is ever cut short. The first child
/// leads: at the start of the row, on top of the stack.
class CardRow extends MultiChildRenderObjectWidget {
  const CardRow({
    required super.children,
    this.slots = equalSlots,
    this.gap = SpaceTokens.s8,
    super.key,
  });

  /// Each child's width in a row [width] wide.
  final List<double> Function(double width) slots;
  final double gap;

  static List<double> equalSlots(double width, [int count = 2]) =>
      List.filled(count, (width - (count - 1) * SpaceTokens.s8) / count);

  @override
  RenderCardRow createRenderObject(BuildContext context) => RenderCardRow(
    slots: slots,
    gap: gap,
    textDirection: Directionality.of(context),
  );

  @override
  void updateRenderObject(BuildContext context, RenderCardRow renderObject) {
    renderObject
      ..slots = slots
      ..gap = gap
      ..textDirection = Directionality.of(context);
  }
}

class _CardRowData extends ContainerBoxParentData<RenderBox> {}

class RenderCardRow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _CardRowData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _CardRowData> {
  RenderCardRow({
    required this._slots,
    required this._gap,
    required this._textDirection,
  });

  List<double> Function(double width) _slots;
  set slots(List<double> Function(double width) value) {
    if (identical(value, _slots)) return;
    _slots = value;
    markNeedsLayout();
  }

  double _gap;
  set gap(double value) {
    if (value == _gap) return;
    _gap = value;
    markNeedsLayout();
  }

  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (value == _textDirection) return;
    _textDirection = value;
    markNeedsLayout();
  }

  /// What a label may run past its slot before it counts as not fitting:
  /// layout rounding.
  static const _slack = 0.5;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _CardRowData) child.parentData = _CardRowData();
  }

  /// Each child's slot in a row [width] wide, or null when one's label
  /// doesn't fit in its slot.
  List<double>? _row(double width) {
    final children = getChildrenAsList();
    final given = _slots(width);
    // `slots` gives one width per child; equal shares otherwise.
    final slots = given.length == children.length
        ? given
        : List.filled(
            children.length,
            (width - (children.length - 1) * _gap) / children.length,
          );
    for (var i = 0; i < children.length; i++) {
      final wanted = children[i].getMaxIntrinsicWidth(double.infinity);
      if (wanted > slots[i] + _slack) return null;
    }
    return slots;
  }

  Size _arrange(BoxConstraints constraints, {required bool dry}) {
    final width = constraints.maxWidth;
    final children = getChildrenAsList();
    if (children.isEmpty) return constraints.smallest;
    Size place(RenderBox child, double childWidth) {
      final tight = BoxConstraints.tightFor(width: childWidth);
      if (dry) return child.getDryLayout(tight);
      child.layout(tight, parentUsesSize: true);
      return child.size;
    }

    final row = _row(width);
    if (row == null) {
      var y = 0.0;
      for (final child in children) {
        if (y > 0) y += _gap;
        final size = place(child, width);
        if (!dry) (child.parentData! as _CardRowData).offset = Offset(0, y);
        y += size.height;
      }
      return constraints.constrain(Size(width, y));
    }
    final sizes = [
      for (var i = 0; i < children.length; i++) place(children[i], row[i]),
    ];
    final height = sizes.map((s) => s.height).reduce(math.max);
    if (!dry) {
      var x = 0.0;
      for (var i = 0; i < children.length; i++) {
        final left = _textDirection == TextDirection.rtl
            ? width - x - row[i]
            : x;
        (children[i].parentData! as _CardRowData).offset = Offset(
          left,
          (height - sizes[i].height) / 2,
        );
        x += row[i] + _gap;
      }
    }
    return constraints.constrain(Size(width, height));
  }

  @override
  void performLayout() {
    size = _arrange(constraints, dry: false);
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      _arrange(constraints, dry: true);

  @override
  double computeMinIntrinsicWidth(double height) => getChildrenAsList()
      .map((c) => c.getMinIntrinsicWidth(height))
      .fold(0, math.max);

  @override
  double computeMaxIntrinsicWidth(double height) {
    final children = getChildrenAsList();
    return children.fold<double>(
          0,
          (sum, c) => sum + c.getMaxIntrinsicWidth(height),
        ) +
        math.max(0, children.length - 1) * _gap;
  }

  @override
  double computeMinIntrinsicHeight(double width) =>
      computeMaxIntrinsicHeight(width);

  @override
  double computeMaxIntrinsicHeight(double width) {
    final children = getChildrenAsList();
    if (children.isEmpty) return 0;
    final row = _row(width);
    if (row == null) {
      return children.fold<double>(
            0,
            (sum, c) => sum + c.getMaxIntrinsicHeight(width),
          ) +
          (children.length - 1) * _gap;
    }
    return [
      for (var i = 0; i < children.length; i++)
        children[i].getMaxIntrinsicHeight(row[i]),
    ].reduce(math.max);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);
}

/// The spend confirmation's action (`States` box 14): `primary`, 52 high,
/// radius 18, Marhey 700 19.
class CardConfirm extends StatelessWidget {
  const CardConfirm({required this.label, required this.onTap, super.key});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => AppButton.primary(
    label: label,
    onTap: onTap,
    size: AppButtonSize.l,
    height: DesignExtras.confirmHeight,
    radius: DesignExtras.confirmRadius,
    labelStyle: DesignExtras.confirmLabel,
  );
}

/// A `ground` button without a lip (`States` box 15, `Fail` boxes 19 and
/// 21): 15/700 ink, centred, with an optional [trailing] chip. Pressed, it
/// fades to 70%; disabled, to 45%.
class CardTile extends StatelessWidget {
  const CardTile({
    required this.label,
    required this.onTap,
    this.trailing,
    this.enabled = true,
    this.semanticLabel,
    this.height = DesignExtras.confirmHeight,
    this.radius = DesignExtras.confirmRadius,
    super.key,
  });

  final String label;
  final VoidCallback onTap;
  final Widget? trailing;
  final bool enabled;
  final String? semanticLabel;
  final double height;
  final double radius;

  static const _pressedOpacity = 0.7;

  @override
  Widget build(BuildContext context) {
    final corners = BorderRadius.circular(radius);
    return Pressable(
      onTap: onTap,
      enabled: enabled,
      pressedOpacity: _pressedOpacity,
      borderRadius: corners,
      semanticLabel: semanticLabel ?? label,
      child: Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: SpaceTokens.s8),
        decoration: BoxDecoration(
          color: ColorTokens.ground,
          borderRadius: corners,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: SpaceTokens.s6,
          children: [
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TypeTokens.row
                    .weight(700)
                    .copyWith(color: ColorTokens.ink),
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}
