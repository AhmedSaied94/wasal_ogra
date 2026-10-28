// The cabin (layer 1, HANDOFF §4.1, `C-Trip`, `Tutorial`), in two parts
// around the windows: behind them the wall, the floor and the back window
// (the tuktuk's roof, open sides and pillars); in front of them the benches.
// Neither changes with the trip, so each is recorded once per size as a
// picture. Everything is placed from the bottom up, so a short scene loses
// the wall first. No garland (research R1).
import 'dart:ui';

import 'package:content_models/content_models.dart';
import 'package:flame/components.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/trip/domain/scene_layout.dart';
import 'package:wassal/features/trip/presentation/scene/scene_space.dart';
import 'package:wassal/features/trip/presentation/scene/trip_game.dart';

enum CabinPart { back, benches }

class CabinComponent extends Component with HasGameReference<TripGame> {
  CabinComponent(this.part);

  final CabinPart part;

  Picture? _picture;
  SceneLayout? _recordedFor;

  @override
  void render(Canvas canvas) {
    final layout = game.layout;
    if (layout == null) return;
    if (!identical(layout, _recordedFor)) {
      _picture?.dispose();
      _picture = _record(layout);
      _recordedFor = layout;
    }
    canvas.drawPicture(_picture!);
  }

  Picture _record(SceneLayout layout) {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    final tuktuk = layout.vehicle == VehicleId.tuktuk;
    switch ((part, tuktuk)) {
      case (CabinPart.back, false):
        _microBack(canvas, layout);
      case (CabinPart.back, true):
        _tuktukBack(canvas, layout);
      case (CabinPart.benches, false):
        _microBenches(canvas, layout);
      case (CabinPart.benches, true):
        _tuktukBench(canvas, layout);
    }
    return recorder.endRecording();
  }

  static Paint _fill(Color color) => Paint()..color = color;

  /// The wall, its top corners rounded into the page.
  static void _wall(Canvas canvas, SceneLayout layout) => canvas.drawRRect(
    RRect.fromRectAndCorners(
      Rect.fromLTWH(0, 0, layout.width, layout.height),
      topLeft: const Radius.circular(RadiusTokens.scene),
      topRight: const Radius.circular(RadiusTokens.scene),
    ),
    _fill(ColorTokens.sceneWall),
  );

  /// Buildings standing in a window: design `(x, y, w, h)`, colour by
  /// order.
  static void _buildings(
    Canvas canvas,
    SceneLayout layout,
    List<(double, double, double, double)> rects,
    double radius,
  ) {
    for (final (i, (x, y, w, h)) in rects.indexed) {
      canvas.drawRRect(
        layout.rrectOf(x, y, w, h, radius),
        _fill(
          DesignExtras.sceneBuildings[i % DesignExtras.sceneBuildings.length],
        ),
      );
    }
  }

  static void _microBack(Canvas canvas, SceneLayout layout) {
    _wall(canvas, layout);
    canvas
      ..drawRect(layout.rectOf(0, 182, 390, 262), _fill(ColorTokens.sceneFloor))
      ..drawRRect(
        layout.rrectOf(120, 10, 150, 52, 16),
        _fill(ColorTokens.sceneSky),
      );
    _buildings(canvas, layout, const [
      (130, 34, 20, 28),
      (154, 24, 24, 38),
      (212, 30, 22, 32),
      (238, 40, 24, 22),
    ], 5);
  }

  /// Each bench under its row's faces, wherever the table puts the row.
  static void _microBenches(Canvas canvas, SceneLayout layout) {
    for (final (row, (x, y, w, h, r), (hx, hy, hw, hh, hr)) in const [
      (
        SeatRow.c,
        (88.0, 104.0, 214.0, 42.0, 16.0),
        (96.0, 108.0, 198.0, 8.0, 4.0),
      ),
      (
        SeatRow.b,
        (46.0, 212.0, 298.0, 50.0, 18.0),
        (54.0, 216.0, 282.0, 9.0, 4.5),
      ),
      (
        SeatRow.a,
        (6.0, 326.0, 378.0, 58.0, 22.0),
        (16.0, 331.0, 358.0, 10.0, 5.0),
      ),
    ]) {
      canvas
        ..drawRRect(
          layout.rowRRectOf(row, x, y, w, h, r),
          _fill(ColorTokens.sceneSeat),
        )
        ..drawRRect(
          layout.rowRRectOf(row, hx, hy, hw, hh, hr),
          _fill(ColorTokens.sceneSeatHi),
        );
    }
  }

  static void _tuktukBack(Canvas canvas, SceneLayout layout) {
    _wall(canvas, layout);
    final frame = _fill(ColorTokens.sceneTyre);
    canvas
      ..drawRect(layout.rectOf(0, 0, 390, 40), frame)
      ..drawRect(layout.rectOf(0, 40, 22, 404), _fill(ColorTokens.sceneSky))
      ..drawRect(layout.rectOf(368, 40, 22, 404), _fill(ColorTokens.sceneSky))
      ..drawRRect(layout.rrectOf(18, 40, 10, 404, 5), frame)
      ..drawRRect(layout.rrectOf(362, 40, 10, 404, 5), frame);
  }

  static void _tuktukBench(Canvas canvas, SceneLayout layout) => canvas
    ..drawRect(layout.rectOf(28, 282, 334, 162), _fill(ColorTokens.sceneFloor))
    ..drawRRect(
      layout.rrectOf(32, 236, 326, 96, 28),
      _fill(ColorTokens.sceneSeat),
    )
    ..drawRRect(
      layout.rrectOf(44, 242, 302, 12, 6),
      _fill(ColorTokens.sceneSeatHi),
    );

  @override
  void onRemove() {
    _picture?.dispose();
    super.onRemove();
  }
}
