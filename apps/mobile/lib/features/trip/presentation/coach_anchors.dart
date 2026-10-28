// Where the coach's targets are on screen (specs/012-m07-onboarding/
// contracts/coach.md "Anchors"): the drawer, each of its cells and the next
// stop's countdown chip report their rects after each layout, and the coach
// layer cuts its hole there. Passengers need no anchor: their hit rects are
// the scene layout's.
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/features/onboarding/domain/tutorial_coach.dart';
import 'package:wassal/features/trip/presentation/trip_scope.dart';

/// The targets' rects in global coordinates, by the target they stand for
/// (`TrayTarget`, `TrayCellTarget`, `StationCountdownTarget`).
final class CoachAnchors extends ChangeNotifier {
  final _rects = <CoachTarget, Rect>{};
  final _owners = <CoachTarget, Object>{};

  /// [target]'s rect, or null before it was laid out.
  Rect? rectOf(CoachTarget target) => _rects[target];

  /// Called after a frame, never during one.
  void _report(CoachTarget target, Rect rect, Object owner) {
    _owners[target] = owner;
    if (_rects[target] == rect) return;
    _rects[target] = rect;
    notifyListeners();
  }

  /// A detached anchor's rect goes, unless another took its target since.
  /// Silent: it happens while the tree is locked.
  void _forget(CoachTarget target, Object owner) {
    if (_owners[target] != owner) return;
    _owners.remove(target);
    _rects.remove(target);
  }
}

/// Reports [child]'s rect as [target]'s to the trip's [CoachAnchors].
class CoachAnchor extends SingleChildRenderObjectWidget {
  const CoachAnchor({required this.target, super.child, super.key});

  final CoachTarget target;

  static CoachAnchors? _anchorsOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<TripScope>()?.anchors;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderCoachAnchor(target, _anchorsOf(context));

  @override
  void updateRenderObject(
    BuildContext context,
    RenderCoachAnchor renderObject,
  ) {
    renderObject
      ..target = target
      ..anchors = _anchorsOf(context);
  }
}

/// [CoachAnchor]'s box: reports its rect after each frame that laid it out
/// or painted it.
class RenderCoachAnchor extends RenderProxyBox {
  RenderCoachAnchor(this._target, this._anchors);

  CoachTarget _target;
  set target(CoachTarget value) {
    if (value == _target) return;
    _anchors?._forget(_target, this);
    _target = value;
    _scheduleReport();
  }

  CoachAnchors? _anchors;
  set anchors(CoachAnchors? value) {
    if (identical(value, _anchors)) return;
    _anchors?._forget(_target, this);
    _anchors = value;
    _scheduleReport();
  }

  bool _scheduled = false;

  @override
  void performLayout() {
    super.performLayout();
    _scheduleReport();
  }

  // A move without a new size (a parent's relayout) repaints.
  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    _scheduleReport();
  }

  /// After the frame, when every offset up the tree is final.
  void _scheduleReport() {
    if (_scheduled || _anchors == null) return;
    _scheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      final anchors = _anchors;
      if (anchors == null || !attached || !hasSize) return;
      anchors._report(_target, localToGlobal(Offset.zero) & size, this);
    });
  }

  // Moved in the tree, it may keep its layout and paint: report anyway.
  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _scheduleReport();
  }

  @override
  void detach() {
    _anchors?._forget(_target, this);
    super.detach();
  }
}
