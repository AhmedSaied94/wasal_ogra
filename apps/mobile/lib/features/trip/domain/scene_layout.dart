// Where everything sits on the trip screen (contracts/scene-layout.md). The
// Flame scene and the Flutter overlays both read this, so they line up by
// construction (research R3). Units are logical points; the origin is the
// scene's top left.
import 'dart:math';

import 'package:content_models/content_models.dart';

/// The top bar's height, above the display cutout's inset.
const topBarHeight = 110.0;

/// The dashboard's height. It is drawn over the scene's last [dashboardOverlap].
const dashboardHeight = 230.0;
const dashboardOverlap = 16.0;

/// From this scene height up, faces keep their minimum sizes.
const compliantSceneHeight = 420.0;

const nearFaceMin = 80.0;
const backFaceMin = 50.0;
const minTouch = 44.0;

/// The windows take this share of the scene's height, at the top.
const _windowsShare = 0.18;

/// The farthest row's faces may rise this far into the windows.
const _rowsTopShare = 0.06;

/// The scene's bottom strip, behind the dashboard's overlap and a margin.
const _rowsBottomInset = 24.0;

/// Room between neighboring faces in a row.
const _columnGap = 8.0;

/// A face's height for its width.
const _faceAspect = 1.15;

/// The part of a farther face the nearer row leaves visible.
const _visibleShare = 0.85;

/// The tuktuk's single row stays about this wide.
const _maxFace = 104.0;

/// Nearer rows are larger: the scale of each row against row A.
double _rowScale(SeatRow row) => switch (row) {
  SeatRow.front => 1.1,
  SeatRow.a => 1.0,
  SeatRow.b => 0.8,
  SeatRow.c => 0.64,
  SeatRow.d => 0.52,
};

/// The column's center as a share of the width, from the viewer's right.
double _columnShare(SeatCol col) => switch (col) {
  SeatCol.r => 5 / 6,
  SeatCol.m => 3 / 6,
  SeatCol.l => 1 / 6,
};

/// The three bands' heights for a screen [height] (contracts/scene-layout.md
/// "Bands"). The bands never shrink; the scene takes the rest.
final class BandHeights {
  factory BandHeights.of(double height, {double topInset = 0}) {
    final top = topBarHeight + topInset;
    return BandHeights._(
      top: top,
      scene: max(0, height - top - dashboardHeight + dashboardOverlap),
    );
  }

  const BandHeights._({required this.top, required this.scene});

  final double top;
  final double scene;
  double get dashboard => dashboardHeight;
  double get overlap => dashboardOverlap;
}

BandHeights bandHeights(double screenHeight, {double topInset = 0}) =>
    BandHeights.of(screenHeight, topInset: topInset);

/// One seat's places in the scene.
final class SeatGeometry {
  const SeatGeometry({
    required this.seatId,
    required this.row,
    required this.col,
    required this.face,
    required this.hit,
    required this.bubbleAnchor,
    required this.tokenAnchor,
  });

  final String seatId;
  final SeatRow row;
  final SeatCol col;

  /// The face (and the head around it). Nearer rows cover farther ones.
  final Rectangle<double> face;

  /// The passenger's tap and drop area: never overlaps another seat's.
  final Rectangle<double> hit;

  /// Above the head, where a bubble's tail points.
  final Point<double> bubbleAnchor;

  /// The hands, where money arrives and leaves.
  final Point<double> tokenAnchor;

  bool get isNearRow => row == SeatRow.front || row == SeatRow.a;
}

/// Every seat's geometry for a scene of [width] × [height].
final class SceneLayout {
  factory SceneLayout(
    List<Seat> seats, {
    required double width,
    required double height,
  }) {
    final rows = {for (final seat in seats) seat.row}.toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    final rowsBottom = height - _rowsBottomInset;
    final rowsTop = height * _rowsTopShare;
    final widest = rows.map(_rowScale).fold(0.0, max);
    final byWidth = min(
      _maxFace,
      (width / 3 - _columnGap) / (widest == 0 ? 1 : widest),
    );
    final faceA = _fit(rows, rowsBottom - rowsTop, byWidth);

    // Baselines, nearest row first: each farther row tucks its chin behind
    // the nearer row's heads, leaving its visible part.
    final baseline = <SeatRow, double>{};
    final faceTop = <SeatRow, double>{};
    double? previousTop;
    for (final row in rows) {
      final h = _faceHeight(row, faceA);
      final bottom = switch (previousTop) {
        null => rowsBottom,
        final top => top + h - _visible(row, faceA),
      };
      baseline[row] = bottom;
      faceTop[row] = bottom - h;
      previousTop = bottom - h;
    }

    final geometry = <String, SeatGeometry>{};
    for (final seat in seats) {
      final f = _rowScale(seat.row) * faceA;
      final cx = width * _columnShare(seat.col);
      final top = faceTop[seat.row]!;
      final face = Rectangle<double>(cx - f / 2, top, f, f * _faceAspect);
      // The hit area ends where the nearest row in front of it, in the
      // same column, starts covering it.
      var hitBottom = baseline[seat.row]!;
      for (final other in seats) {
        if (other.col == seat.col && other.row.index < seat.row.index) {
          hitBottom = min(hitBottom, faceTop[other.row]!);
        }
      }
      final hitWidth = max(f, minTouch);
      geometry[seat.seatId] = SeatGeometry(
        seatId: seat.seatId,
        row: seat.row,
        col: seat.col,
        face: face,
        hit: Rectangle<double>(
          cx - hitWidth / 2,
          top,
          hitWidth,
          hitBottom - top,
        ),
        bubbleAnchor: Point(cx, top),
        tokenAnchor: Point(cx, face.bottom - f * 0.15),
      );
    }
    return SceneLayout._(
      width: width,
      height: height,
      faceA: faceA,
      seats: Map.unmodifiable(geometry),
    );
  }

  const SceneLayout._({
    required this.width,
    required this.height,
    required this.faceA,
    required this.seats,
  });

  final double width;
  final double height;

  /// Row A's face width; other rows scale from it.
  final double faceA;

  /// By seat id.
  final Map<String, SeatGeometry> seats;

  Rectangle<double> get bounds => Rectangle(0, 0, width, height);

  /// The windows, where the street and the station signs pass.
  Rectangle<double> get windows =>
      Rectangle(0, 0, width, height * _windowsShare);

  /// Where the driver's hand rests: bottom left, above the dashboard.
  Point<double> get driverAnchor =>
      Point(width * 0.12, height - _rowsBottomInset - 20);

  /// The anchor of [holder]'s hands: a seat's, or the driver's.
  Point<double> anchorOf(String? seatId) =>
      seats[seatId]?.tokenAnchor ?? driverAnchor;

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
      (a.y + (b.y - a.y) * t + faceA * 0.3)
          .clamp(half, max(half, height - dashboardOverlap - half))
          .toDouble(),
    );
  }
}

double _faceHeight(SeatRow row, double faceA) =>
    _rowScale(row) * faceA * _faceAspect;

double _visible(SeatRow row, double faceA) =>
    max(_faceHeight(row, faceA) * _visibleShare, minTouch);

/// The largest row-A face width, at most [cap], whose rows fit in [room].
double _fit(List<SeatRow> rows, double room, double cap) {
  double needed(double faceA) {
    var total = 0.0;
    for (final (i, row) in rows.indexed) {
      total += i == 0 ? _faceHeight(row, faceA) : _visible(row, faceA);
    }
    return total;
  }

  if (rows.isEmpty || needed(cap) <= room) return cap;
  var low = 0.0;
  var high = cap;
  for (var i = 0; i < 40; i++) {
    final mid = (low + high) / 2;
    if (needed(mid) <= room) {
      low = mid;
    } else {
      high = mid;
    }
  }
  return low;
}
