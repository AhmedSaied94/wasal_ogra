// Where everything sits on the trip screen (specs/008.5-m21-design-refresh,
// contracts/trip-layout.md). The Flame scene and the Flutter overlays both
// read this, so they line up by construction (M02 research R3). Units are
// logical points; the scene's origin is its top left.
//
// The design's seat table is copied here as constants: the generated tokens
// import Flutter, which the domain can't. scene_layout_test.dart checks the
// copy against `LayoutTokens.trip*`.
import 'dart:math';

import 'package:content_models/content_models.dart';

/// The HUD under the top inset: the title row and the station strip.
const tripHudHeight = 114.0;

/// Between the HUD and the scene, when the screen has room for it.
const tripGap = 8.0;

/// The dashboard, drawn over the scene's last [dashboardOverlap].
const dashboardHeight = 258.0;
const dashboardOverlap = 16.0;

/// The design's scene.
const designSceneWidth = 390.0;
const designSceneHeight = 444.0;

/// The most a short scene loses from its top: the wall and the back window,
/// never a face or a tag.
const maxCrop = 36.0;

/// Below this the cropped scene scales down: M02's exception (research R7).
const unscaledSceneMin = designSceneHeight - maxCrop;

/// Over this width the zones keep the design's width, centred.
const maxZonesWidth = 430.0;

/// The top inset a phone gets at least (HANDOFF §2.4).
const minTopInset = 24.0;

const nearFaceMin = 80.0;
const backFaceMin = 50.0;
const minTouch = 44.0;

/// The rig's head radius at scale 1: a face is twice this times the rig
/// scale wide.
const rigHeadRadius = 42.0;

/// The front seat's face sits this far from the scene's end edge.
const frontFromEnd = 40.0;
const microOldFrontY = 392.0;

/// The driver's hand, where his notes rest.
const driverHand = Point<double>(162, 398);

/// The smallest screen height that keeps every minimum, for a top [inset].
double minCompliantHeight(double inset) =>
    inset +
    tripHudHeight +
    dashboardHeight -
    dashboardOverlap +
    unscaledSceneMin;

/// A hit rect from a face's centre.
final class HitSpec {
  const HitSpec(this.dx, this.dy, this.width, this.height);

  final double dx;
  final double dy;
  final double width;
  final double height;
}

/// A row of seats in the design's scene.
final class RowSpec {
  const RowSpec({
    required this.rigScale,
    required this.y,
    required this.x,
    required this.tag,
    required this.hit,
  });

  final double rigScale;

  /// The faces' centre.
  final double y;

  /// The columns `l`, `m` and `r`, left to right.
  final List<double> x;

  /// The station tag's size.
  final double tag;
  final HitSpec hit;

  /// The narrowest gap between two columns: no hit area is wider.
  double get spacing => min(x[1] - x[0], x[2] - x[1]);

  double xOf(SeatCol col) => switch (col) {
    SeatCol.l => x[0],
    SeatCol.m => x[1],
    SeatCol.r => x[2],
  };
}

/// The old microbus (HANDOFF §4.2, `C-Trip`).
const microOldRows = <SeatRow, RowSpec>{
  SeatRow.c: RowSpec(
    rigScale: 0.625,
    y: 92,
    x: [126, 195, 264],
    tag: 24,
    hit: HitSpec(-34, -30, 68, 80),
  ),
  SeatRow.b: RowSpec(
    rigScale: 0.8,
    y: 196,
    x: [98, 195, 292],
    tag: 26,
    hit: HitSpec(-46, -36, 92, 100),
  ),
  SeatRow.a: RowSpec(
    rigScale: 1,
    y: 308,
    x: [62, 176, 290],
    tag: 30,
    hit: HitSpec(-56, -46, 112, 112),
  ),
};

/// `A_r` gives way to the front seat below it.
const microOldNearRightHit = HitSpec(-56, -46, 100, 80);
const microOldFrontHit = HitSpec(-50, -48, 90, 80);
const microOldFrontTag = 30.0;

/// The tuktuk's one bench (`Tutorial`, research R7).
const tuktukRow = RowSpec(
  rigScale: 1.15,
  y: 308,
  x: [62, 195, 328],
  tag: 30,
  hit: HitSpec(-60, -52, 120, 120),
);

/// The glass bands, as design `(left, top, right, bottom)`: both side
/// windows of `C-Trip`, the windscreen of `Tutorial`.
const microSideWindows = (0.0, 34.0, 390.0, 176.0);
const tuktukWindscreen = (70.0, 62.0, 320.0, 180.0);

/// Tags sit at `face + this × rig scale`, the front seat's at
/// [frontTagOffset].
const tagOffset = Point<double>(-38, 46);
const frontTagOffset = Point<double>(-32, 18);

/// A bubble's tail tip is this far above the head.
const bubbleGap = 8.0;

/// A note in a passenger's hands: this far under the face's centre, times
/// the rig scale.
const handsBelow = 50.0;

/// The screen's zones, top to bottom (contracts/trip-layout.md "Zones").
final class TripZones {
  factory TripZones({
    required double width,
    required double height,
    required double viewPaddingTop,
  }) {
    final inset = max(viewPaddingTop, minTopInset);
    final room =
        height - inset - tripHudHeight - dashboardHeight + dashboardOverlap;
    final gap = (room - designSceneHeight).clamp(0.0, tripGap);
    final zonesWidth = width > maxZonesWidth ? designSceneWidth : width;
    return TripZones._(
      inset: inset,
      room: room,
      gap: gap,
      scene: max(0, room - gap),
      width: zonesWidth,
      left: (width - zonesWidth) / 2,
    );
  }

  const TripZones._({
    required this.inset,
    required this.room,
    required this.gap,
    required this.scene,
    required this.width,
    required this.left,
  });

  /// `max(viewPadding.top, 24)`.
  final double inset;

  /// The gap and the scene together: `S0`.
  final double room;
  final double gap;
  final double scene;

  /// The zones' width, and their left edge when centred.
  final double width;
  final double left;

  double get hud => tripHudHeight;
  double get dashboard => dashboardHeight;
  double get overlap => dashboardOverlap;
  double get sceneTop => inset + hud + gap;
  double get dashboardTop => sceneTop + scene - overlap;
}

/// One seat's places in the scene.
final class SeatLayout {
  const SeatLayout({
    required this.seatId,
    required this.row,
    required this.col,
    required this.face,
    required this.rigScale,
    required this.tag,
    required this.tagSize,
    required this.hit,
    required this.bubbleAnchor,
    required this.tokenAnchor,
  });

  final String seatId;
  final SeatRow row;
  final SeatCol col;

  /// The head's centre.
  final Point<double> face;

  /// The rig's scale here, the scene's `scale` included.
  final double rigScale;

  /// The station tag's centre, and its size (24, 26 or 30).
  final Point<double> tag;
  final double tagSize;

  /// The passenger's tap and drop area: at least 44×44, never overlapping
  /// another seat's.
  final Rectangle<double> hit;

  /// The bubble's tail tip, [bubbleGap] above the head.
  final Point<double> bubbleAnchor;

  /// The hands, where money arrives and leaves.
  final Point<double> tokenAnchor;

  double get faceWidth => 2 * rigHeadRadius * rigScale;

  /// The head's square.
  Rectangle<double> get head => Rectangle(
    face.x - faceWidth / 2,
    face.y - faceWidth / 2,
    faceWidth,
    faceWidth,
  );

  bool get isNearRow => row == SeatRow.front || row == SeatRow.a;
}

/// Every seat's places in a scene of [width] × [height] for [vehicle]
/// (contracts/trip-layout.md "Height", "Width", "Seats").
final class SceneLayout {
  factory SceneLayout(
    List<Seat> seats, {
    required VehicleId vehicle,
    required double width,
    required double height,
  }) {
    final crop = (designSceneHeight - height).clamp(0.0, maxCrop);
    final scale = height < unscaledSceneMin ? height / unscaledSceneMin : 1.0;
    final xFactor = width / designSceneWidth;
    double y(double designY) => _sceneY(designY, height, scale);

    final layouts = <String, SeatLayout>{};
    for (final seat in seats) {
      final spec = _specOf(vehicle, seat);
      final isFront = seat.row == SeatRow.front;
      final face = Point(
        isFront
            ? width - frontFromEnd * scale
            : spec.row.xOf(seat.col) * xFactor,
        y(spec.y),
      );
      final rig = spec.row.rigScale * scale;
      var left = face.x + spec.hit.dx * scale;
      var right = left + spec.hit.width * scale;
      var top = face.y + spec.hit.dy * scale;
      var bottom = top + spec.hit.height * scale;
      // Narrowed to the row's seat spacing, so neighbours never overlap.
      if (!isFront) {
        final half = spec.row.spacing * xFactor / 2;
        left = max(left, face.x - half);
        right = min(right, face.x + half);
      }
      left = max(0, left);
      right = min(width, right);
      top = max(0, top);
      bottom = min(height, bottom);
      // Never under 44×44, around its centre.
      var w = right - left;
      var h = bottom - top;
      if (w < minTouch) {
        left = (left + right - minTouch) / 2;
        w = minTouch;
      }
      if (h < minTouch) {
        top = (top + bottom - minTouch) / 2;
        h = minTouch;
      }
      layouts[seat.seatId] = SeatLayout(
        seatId: seat.seatId,
        row: seat.row,
        col: seat.col,
        face: face,
        rigScale: rig,
        tag: face + (isFront ? frontTagOffset * scale : tagOffset * rig),
        tagSize: spec.row.tag,
        hit: Rectangle(left, top, w, h),
        bubbleAnchor: Point(face.x, face.y - rigHeadRadius * rig - bubbleGap),
        tokenAnchor: Point(face.x, face.y + handsBelow * rig),
      );
    }
    return SceneLayout._(
      width: width,
      height: height,
      crop: crop,
      scale: scale,
      xFactor: xFactor,
      vehicle: vehicle,
      hand: Point(driverHand.x * xFactor, y(driverHand.y)),
      seats: Map.unmodifiable(layouts),
    );
  }

  const SceneLayout._({
    required this.width,
    required this.height,
    required this.crop,
    required this.scale,
    required this.xFactor,
    required this.vehicle,
    required this.hand,
    required this.seats,
  });

  final double width;
  final double height;

  /// Points cut from the top of the cabin: `max(0, 444 − height)`, at most
  /// 36.
  final double crop;

  /// 1, or `height / 408` below 408 (faces and drawn sizes only).
  final double scale;

  /// `width / 390`.
  final double xFactor;
  final VehicleId vehicle;

  /// The driver's hand, where his notes rest.
  final Point<double> hand;

  /// By seat id.
  final Map<String, SeatLayout> seats;

  Rectangle<double> get bounds => Rectangle(0, 0, width, height);

  /// The glass at the top of the cabin, where the street passes: the side
  /// windows of a microbus, the tuktuk's windscreen.
  Rectangle<double> get windows {
    final (left, top, right, bottom) = vehicle == VehicleId.tuktuk
        ? tuktukWindscreen
        : microSideWindows;
    final a = place(left, top);
    final b = place(right, bottom);
    return Rectangle(a.x, a.y, b.x - a.x, b.y - a.y);
  }

  /// Where a design point of the scene lands: x spread, y from the bottom.
  Point<double> place(double designX, double designY) =>
      Point(designX * xFactor, _sceneY(designY, height, scale));

  /// The anchor of [holder]'s hands: a seat's, or the driver's.
  Point<double> anchorOf(String? seatId) => seats[seatId]?.tokenAnchor ?? hand;

  /// Where a note that fell [progressPermille] of the way from [from] to
  /// [to] lies: a little lower, on the floor, with room for its tap area
  /// inside the scene and above the dashboard.
  Point<double> floorAt(String? from, String? to, int progressPermille) {
    final a = anchorOf(from);
    final b = anchorOf(to);
    final t = progressPermille / 1000;
    const half = minTouch / 2;
    return Point(
      (a.x + (b.x - a.x) * t).clamp(half, max(half, width - half)).toDouble(),
      (a.y + (b.y - a.y) * t + 24 * scale)
          .clamp(half, max(half, height - dashboardOverlap - half))
          .toDouble(),
    );
  }
}

/// Where a design y lands in a scene of [height]. Seats keep their distance
/// from the scene's bottom: a taller scene grows the wall, a shorter one
/// loses it first, then scales from the crop line.
double _sceneY(double designY, double height, double scale) => scale < 1
    ? (designY - maxCrop) * scale
    : designY + height - designSceneHeight;

/// A seat's row and its hit area in [vehicle].
typedef _Spec = ({RowSpec row, HitSpec hit, double y});

_Spec _specOf(VehicleId vehicle, Seat seat) {
  if (vehicle == VehicleId.tuktuk) {
    return (row: tuktukRow, hit: tuktukRow.hit, y: tuktukRow.y);
  }
  // The other microbuses use the old one's table until their art arrives;
  // row D (phase 2) sits with the back row.
  final row = switch (seat.row) {
    SeatRow.front || SeatRow.a => microOldRows[SeatRow.a]!,
    SeatRow.b => microOldRows[SeatRow.b]!,
    SeatRow.c || SeatRow.d => microOldRows[SeatRow.c]!,
  };
  if (seat.row == SeatRow.front) {
    return (
      row: RowSpec(
        rigScale: row.rigScale,
        y: microOldFrontY,
        x: row.x,
        tag: microOldFrontTag,
        hit: microOldFrontHit,
      ),
      hit: microOldFrontHit,
      y: microOldFrontY,
    );
  }
  final hit = seat.row == SeatRow.a && seat.col == SeatCol.r
      ? microOldNearRightHit
      : row.hit;
  return (row: row, hit: hit, y: row.y);
}
