// Where everything sits on the trip screen (specs/008.5-m21-design-refresh,
// contracts/trip-layout.md; under the threshold, specs/012-m07-onboarding
// contracts/compact-trip-layout.md). The Flame scene and the Flutter
// overlays both read this, so they line up by construction (M02 research
// R3). Units are logical points; the scene's origin is its top left.
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

/// From this scene up, 008.5's seat table with its crop; under it, the
/// compact table (M07).
const unscaledSceneMin = designSceneHeight - maxCrop;

/// The compact profile's HUD and dashboard (M07).
const compactHudHeight = 72.0;
const compactDashboardHeight = 226.0;

/// The scene the compact table is drawn for (360×640, T 24). Under it the
/// table scales, outside the supported range.
const compactSceneHeight = 334.0;

/// A bubble's anchor keeps this far inside the scene's top.
const bubbleTopMargin = 10.0;

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

/// The smallest screen height for the regular profile, for a top [inset];
/// under it the trip takes the compact one.
double minCompliantHeight(double inset) =>
    inset +
    tripHudHeight +
    dashboardHeight -
    dashboardOverlap +
    unscaledSceneMin;

/// The trip screen's two layouts (M07 research R19).
enum TripProfile { regular, compact }

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

/// The compact `micro_old` table at a [compactSceneHeight] scene. The near
/// rows' 0.952 is exactly 80/84, so their faces are 80.
const _compactNearRig = nearFaceMin / (2 * rigHeadRadius);
const microOldCompactRows = <SeatRow, RowSpec>{
  SeatRow.c: RowSpec(
    rigScale: 0.6,
    y: 46,
    x: [126, 195, 264],
    tag: 24,
    hit: HitSpec(-34, -30, 68, 80),
  ),
  SeatRow.b: RowSpec(
    rigScale: 0.66,
    y: 122,
    x: [98, 195, 292],
    tag: 26,
    hit: HitSpec(-46, -36, 92, 100),
  ),
  SeatRow.a: RowSpec(
    rigScale: _compactNearRig,
    y: 206,
    x: [62, 176, 290],
    tag: 30,
    hit: HitSpec(-56, -46, 112, 112),
  ),
};
const microOldCompactFrontY = 284.0;
const compactDriverHandY = 290.0;

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

/// The screen's zones, top to bottom (contracts/trip-layout.md "Zones";
/// compact-trip-layout.md "Profiles").
final class TripZones {
  factory TripZones({
    required double width,
    required double height,
    required double viewPaddingTop,
  }) {
    final inset = max(viewPaddingTop, minTopInset);
    final profile = height < minCompliantHeight(inset)
        ? TripProfile.compact
        : TripProfile.regular;
    final (hud, dashboard) = switch (profile) {
      TripProfile.regular => (tripHudHeight, dashboardHeight),
      TripProfile.compact => (compactHudHeight, compactDashboardHeight),
    };
    final room = height - inset - hud - dashboard + dashboardOverlap;
    final gap = profile == TripProfile.compact
        ? 0.0
        : (room - designSceneHeight).clamp(0.0, tripGap);
    final zonesWidth = width > maxZonesWidth ? designSceneWidth : width;
    return TripZones._(
      profile: profile,
      inset: inset,
      hud: hud,
      dashboard: dashboard,
      room: room,
      gap: gap,
      scene: max(0, room - gap),
      width: zonesWidth,
      left: (width - zonesWidth) / 2,
    );
  }

  const TripZones._({
    required this.profile,
    required this.inset,
    required this.hud,
    required this.dashboard,
    required this.room,
    required this.gap,
    required this.scene,
    required this.width,
    required this.left,
  });

  final TripProfile profile;

  /// `max(viewPadding.top, 24)`.
  final double inset;
  final double hud;
  final double dashboard;

  /// The gap and the scene together: `S0`.
  final double room;
  final double gap;
  final double scene;

  /// The zones' width, and their left edge when centred.
  final double width;
  final double left;

  bool get compact => profile == TripProfile.compact;
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
/// (contracts/trip-layout.md "Height", "Width", "Seats"; under 408 pt,
/// compact-trip-layout.md "Seats").
final class SceneLayout {
  factory SceneLayout(
    List<Seat> seats, {
    required VehicleId vehicle,
    required double width,
    required double height,
  }) {
    final compact = height < unscaledSceneMin;
    final crop = (designSceneHeight - height).clamp(0.0, maxCrop);
    final scale = height < compactSceneHeight
        ? height / compactSceneHeight
        : 1.0;
    final xFactor = width / designSceneWidth;
    double y(double tableY) => _tableY(tableY, height, scale, compact: compact);

    final specs = {
      for (final seat in seats)
        seat.seatId: _specOf(vehicle, seat.row, seat.col, compact),
    };
    final hits = <String, Rectangle<double>>{};
    final faces = <String, Point<double>>{};
    for (final seat in seats) {
      final spec = specs[seat.seatId]!;
      final isFront = seat.row == SeatRow.front;
      final face = Point(
        isFront
            ? width - frontFromEnd * scale
            : spec.row.xOf(seat.col) * xFactor,
        y(spec.y),
      );
      faces[seat.seatId] = face;
      // 008.5's rect, times the compact table's share of its rig scale.
      final k = spec.hitScale * scale;
      var left = face.x + spec.hit.dx * k;
      var right = left + spec.hit.width * k;
      // Narrowed to the row's seat spacing, so neighbours never overlap.
      if (!isFront) {
        final half = spec.row.spacing * xFactor / 2;
        left = max(left, face.x - half);
        right = min(right, face.x + half);
      }
      final top = face.y + spec.hit.dy * k;
      hits[seat.seatId] = Rectangle(
        left,
        top,
        right - left,
        spec.hit.height * k,
      );
    }
    if (compact) _apart(hits, seats);

    final layouts = <String, SeatLayout>{};
    for (final seat in seats) {
      final spec = specs[seat.seatId]!;
      final isFront = seat.row == SeatRow.front;
      final face = faces[seat.seatId]!;
      final rig = spec.row.rigScale * scale;
      layouts[seat.seatId] = SeatLayout(
        seatId: seat.seatId,
        row: seat.row,
        col: seat.col,
        face: face,
        rigScale: rig,
        tag: face + (isFront ? frontTagOffset * scale : tagOffset * rig),
        tagSize: spec.row.tag,
        hit: _atLeastTouch(hits[seat.seatId]!, width, height),
        bubbleAnchor: Point(
          face.x,
          max(bubbleTopMargin, face.y - rigHeadRadius * rig - bubbleGap),
        ),
        tokenAnchor: Point(face.x, face.y + handsBelow * rig),
      );
    }
    final handY = vehicle != VehicleId.tuktuk && compact
        ? compactDriverHandY
        : driverHand.y - (compact ? designSceneHeight - compactSceneHeight : 0);
    return SceneLayout._(
      width: width,
      height: height,
      crop: crop,
      scale: scale,
      xFactor: xFactor,
      vehicle: vehicle,
      compact: compact,
      hand: Point(driverHand.x * xFactor, y(handY)),
      rowY: {
        for (final row in SeatRow.values)
          row: (
            design: _designRowY(vehicle, row),
            here: y(_specOf(vehicle, row, SeatCol.m, compact).y),
          ),
      },
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
    required this.compact,
    required this.hand,
    required this._rowY,
    required this.seats,
  });

  final double width;
  final double height;

  /// Points cut from the top of the cabin: `max(0, 444 − height)`, at most
  /// 36.
  final double crop;

  /// 1, or `height / 334` below 334 (faces and drawn sizes only).
  final double scale;

  /// On the compact table: a scene under 408 (M07).
  final bool compact;

  /// Each row's faces: on the design, and here.
  final Map<SeatRow, ({double design, double here})> _rowY;

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

  /// Where a design point that belongs to [row] lands, such as its bench:
  /// as far from the row's faces as on the design. On 008.5's table, the
  /// same as [place].
  Point<double> placeOnRow(SeatRow row, double designX, double designY) {
    final y = _rowY[row]!;
    return Point(designX * xFactor, y.here + (designY - y.design) * scale);
  }

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
/// loses it first; under the compact frame, everything scales from its top.
double _sceneY(double designY, double height, double scale) => scale < 1
    ? (designY - (designSceneHeight - compactSceneHeight)) * scale
    : designY + height - designSceneHeight;

/// Where a seat table's y lands: 008.5's from the 444 frame, the compact
/// table's from the 334 one.
double _tableY(
  double tableY,
  double height,
  double scale, {
  required bool compact,
}) {
  if (!compact) return tableY + height - designSceneHeight;
  return scale < 1 ? tableY * scale : tableY + height - compactSceneHeight;
}

/// A hit rect, inside the scene and at least 44×44 around its centre.
Rectangle<double> _atLeastTouch(
  Rectangle<double> rect,
  double width,
  double height,
) {
  var left = max(0.0, rect.left);
  var top = max(0.0, rect.top);
  final right = min(width, rect.right);
  final bottom = min(height, rect.bottom);
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
  return Rectangle(left, top, w, h);
}

/// The compact table's rects, apart (compact-trip-layout.md "Hit rects"):
/// two rows that meet are cut at the middle of their overlap; the front
/// seat keeps its whole rect, and a seat it meets gives way along the
/// shorter side of the overlap.
void _apart(Map<String, Rectangle<double>> hits, List<Seat> seats) {
  for (var i = 0; i < seats.length; i++) {
    for (var j = i + 1; j < seats.length; j++) {
      final a = seats[i];
      final b = seats[j];
      final ra = hits[a.seatId]!;
      final rb = hits[b.seatId]!;
      final overlap = ra.intersection(rb);
      // Neighbours that only touch: rounding, not an overlap.
      if (overlap == null ||
          overlap.width < _touching ||
          overlap.height < _touching) {
        continue;
      }
      if (a.row == SeatRow.front || b.row == SeatRow.front) {
        final (front, other) = a.row == SeatRow.front ? (a, b) : (b, a);
        hits[other.seatId] = _giveWay(hits[other.seatId]!, hits[front.seatId]!);
        continue;
      }
      if (a.row == b.row) {
        // Side by side: cut at the middle across.
        final (start, end) = ra.left <= rb.left ? (a, b) : (b, a);
        final l = hits[start.seatId]!;
        final r = hits[end.seatId]!;
        final middle = (r.left + l.right) / 2;
        hits[start.seatId] = Rectangle(
          l.left,
          l.top,
          middle - l.left,
          l.height,
        );
        hits[end.seatId] = Rectangle(middle, r.top, r.right - middle, r.height);
        continue;
      }
      // Different rows: one above the other.
      final (upper, lower) = ra.top <= rb.top ? (a, b) : (b, a);
      final up = hits[upper.seatId]!;
      final down = hits[lower.seatId]!;
      final middle = (down.top + up.bottom) / 2;
      hits[upper.seatId] = Rectangle(
        up.left,
        up.top,
        up.width,
        middle - up.top,
      );
      hits[lower.seatId] = Rectangle(
        down.left,
        middle,
        down.width,
        down.bottom - middle,
      );
    }
  }
}

/// Less than this of overlap is two edges touching.
const _touching = 0.001;

/// [rect] cut back from [winner] along the shorter side of their overlap.
Rectangle<double> _giveWay(Rectangle<double> rect, Rectangle<double> winner) {
  final overlap = rect.intersection(winner)!;
  if (overlap.height <= overlap.width) {
    return rect.top < winner.top
        ? Rectangle(rect.left, rect.top, rect.width, winner.top - rect.top)
        : Rectangle(
            rect.left,
            winner.bottom,
            rect.width,
            rect.bottom - winner.bottom,
          );
  }
  return rect.left < winner.left
      ? Rectangle(rect.left, rect.top, winner.left - rect.left, rect.height)
      : Rectangle(
          winner.right,
          rect.top,
          rect.right - winner.right,
          rect.height,
        );
}

/// A seat's row, its hit area and its face's y, in its table's frame; and
/// how much of 008.5's hit rect it keeps.
typedef _Spec = ({RowSpec row, HitSpec hit, double y, double hitScale});

/// [row]'s faces on the design (444 frame), for [placeOnRow].
double _designRowY(VehicleId vehicle, SeatRow row) =>
    _specOf(vehicle, row, SeatCol.m, false).y;

_Spec _specOf(VehicleId vehicle, SeatRow seatRow, SeatCol col, bool compact) {
  if (vehicle == VehicleId.tuktuk) {
    // One bench, `scene − 136` on either table.
    final y = compact
        ? tuktukRow.y - (designSceneHeight - compactSceneHeight)
        : tuktukRow.y;
    return (row: tuktukRow, hit: tuktukRow.hit, y: y, hitScale: 1);
  }
  // The other microbuses use the old one's table until their art arrives;
  // row D (phase 2) sits with the back row.
  final tableRow = switch (seatRow) {
    SeatRow.front || SeatRow.a => SeatRow.a,
    SeatRow.b => SeatRow.b,
    SeatRow.c || SeatRow.d => SeatRow.c,
  };
  final design = microOldRows[tableRow]!;
  final row = compact ? microOldCompactRows[tableRow]! : design;
  final hitScale = row.rigScale / design.rigScale;
  if (seatRow == SeatRow.front) {
    final y = compact ? microOldCompactFrontY : microOldFrontY;
    return (
      row: RowSpec(
        rigScale: row.rigScale,
        y: y,
        x: row.x,
        tag: microOldFrontTag,
        hit: microOldFrontHit,
      ),
      hit: microOldFrontHit,
      y: y,
      hitScale: hitScale,
    );
  }
  final hit = seatRow == SeatRow.a && col == SeatCol.r
      ? microOldNearRightHit
      : design.hit;
  return (row: row, hit: hit, y: row.y, hitScale: hitScale);
}
