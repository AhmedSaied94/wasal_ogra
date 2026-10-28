import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/trip/domain/scene_layout.dart';

// The trip's zones and seats (specs/008.5-m21-design-refresh,
// contracts/trip-layout.md): the room for the scene, its crop and scale, the
// x spread, the `micro_old` and `tuktuk` seat tables, hit areas and the
// minimum sizes.

List<Seat> seatsOf(String vehicle) {
  final json = jsonDecode(
    File('../../content/examples/sample/vehicles/$vehicle.json')
        .readAsStringSync(),
  ) as Map<String, Object?>;
  return [
    for (final seat in json['seats']! as List<Object?>)
      Seat.fromJson(seat! as Map<String, dynamic>),
  ];
}

SceneLayout microOld(double width, double height) => SceneLayout(
  seatsOf('micro_old'),
  vehicle: VehicleId.microOld,
  width: width,
  height: height,
);

SceneLayout tuktuk(double width, double height) => SceneLayout(
  seatsOf('tuktuk'),
  vehicle: VehicleId.tuktuk,
  width: width,
  height: height,
);

bool overlaps(Rectangle<double> a, Rectangle<double> b) {
  final i = a.intersection(b);
  return i != null && i.width > 0.001 && i.height > 0.001;
}

void expectPoint(Point<double> actual, Point<double> expected, String why) {
  expect(actual.x, closeTo(expected.x, 0.01), reason: '$why x');
  expect(actual.y, closeTo(expected.y, 0.01), reason: '$why y');
}

void expectRect(
  Rectangle<double> actual,
  Rectangle<double> expected,
  String why,
) {
  expect(actual.left, closeTo(expected.left, 0.01), reason: '$why left');
  expect(actual.top, closeTo(expected.top, 0.01), reason: '$why top');
  expect(actual.width, closeTo(expected.width, 0.01), reason: '$why width');
  expect(actual.height, closeTo(expected.height, 0.01), reason: '$why height');
}

/// No two hit areas overlap, and none is under 44×44.
void expectHitAreasApart(SceneLayout layout) {
  final all = layout.seats.values.toList();
  for (final seat in all) {
    expect(seat.hit.width, greaterThanOrEqualTo(minTouch), reason: seat.seatId);
    expect(
      seat.hit.height,
      greaterThanOrEqualTo(minTouch),
      reason: seat.seatId,
    );
  }
  for (var i = 0; i < all.length; i++) {
    for (var j = i + 1; j < all.length; j++) {
      expect(
        overlaps(all[i].hit, all[j].hit),
        isFalse,
        reason:
            '${all[i].seatId} ${all[i].hit} and ${all[j].seatId} '
            '${all[j].hit}',
      );
    }
  }
}

/// `C-Trip`'s seat table (contracts/trip-layout.md "Seats: `micro_old`").
const _table = <String, ({double x, double y, double rig, double tag})>{
  'C_l': (x: 126, y: 92, rig: 0.625, tag: 24),
  'C_m': (x: 195, y: 92, rig: 0.625, tag: 24),
  'C_r': (x: 264, y: 92, rig: 0.625, tag: 24),
  'B_l': (x: 98, y: 196, rig: 0.8, tag: 26),
  'B_m': (x: 195, y: 196, rig: 0.8, tag: 26),
  'B_r': (x: 292, y: 196, rig: 0.8, tag: 26),
  'A_l': (x: 62, y: 308, rig: 1, tag: 30),
  'A_m': (x: 176, y: 308, rig: 1, tag: 30),
  'A_r': (x: 290, y: 308, rig: 1, tag: 30),
  'front_r': (x: 350, y: 392, rig: 1, tag: 30),
};

/// The table's hit rects, from the face centre.
const _hits = <String, Rectangle<double>>{
  'C': Rectangle(-34, -30, 68, 80),
  'B': Rectangle(-46, -36, 92, 100),
  'A': Rectangle(-56, -46, 112, 112),
  'A_r': Rectangle(-56, -46, 100, 80),
  'front_r': Rectangle(-50, -48, 90, 80),
};

/// The compact `micro_old` table at a 334 scene, 390 wide
/// (contracts/compact-trip-layout.md "`micro_old`, compact"). The near rows'
/// 0.952 is 80/84: their faces are exactly 80.
const _compact = <String, ({double x, double y, double rig, double tag})>{
  'C_l': (x: 126, y: 46, rig: 0.6, tag: 24),
  'C_m': (x: 195, y: 46, rig: 0.6, tag: 24),
  'C_r': (x: 264, y: 46, rig: 0.6, tag: 24),
  'B_l': (x: 98, y: 122, rig: 0.66, tag: 26),
  'B_m': (x: 195, y: 122, rig: 0.66, tag: 26),
  'B_r': (x: 292, y: 122, rig: 0.66, tag: 26),
  'A_l': (x: 62, y: 206, rig: 80 / 84, tag: 30),
  'A_m': (x: 176, y: 206, rig: 80 / 84, tag: 30),
  'A_r': (x: 290, y: 206, rig: 80 / 84, tag: 30),
  'front_r': (x: 350, y: 284, rig: 80 / 84, tag: 30),
};

void main() {
  group('zones', () {
    test('390×844 with the design inset: gap 8, scene 444, top at 158', () {
      final zones = TripZones(width: 390, height: 844, viewPaddingTop: 36);
      expect(zones.inset, 36);
      expect(zones.hud, 114);
      expect(zones.room, 452);
      expect(zones.gap, 8);
      expect(zones.scene, 444);
      expect(zones.sceneTop, 158);
      expect(zones.dashboard, 258);
      expect(zones.overlap, 16);
      expect(zones.dashboardTop, 586);
      final layout = microOld(390, zones.scene);
      expect(layout.crop, 0);
      expect(layout.scale, 1);
    });

    test('the A06: no gap, a 420 scene cropped by 24, not scaled', () {
      // Its cutout is under 24 pt.
      final zones = TripZones(width: 360, height: 800, viewPaddingTop: 10);
      expect(zones.inset, 24);
      expect(zones.room, 420);
      expect(zones.gap, 0);
      expect(zones.scene, 420);
      final layout = microOld(360, zones.scene);
      expect(layout.crop, 24);
      expect(layout.scale, 1);
    });

    test('a room of 448 keeps the 444 scene with a gap of 4', () {
      final zones = TripZones(
        width: 390,
        height: 448 + 36 + 114 + 258 - 16,
        viewPaddingTop: 36,
      );
      expect(zones.room, 448);
      expect(zones.gap, 4);
      expect(zones.scene, 444);
    });

    test('a scene of 408 is the last on 008.5\'s table, cropped by 36', () {
      final zones = TripZones(width: 360, height: 788, viewPaddingTop: 24);
      expect(zones.profile, TripProfile.regular);
      expect(zones.scene, 408);
      final layout = microOld(360, zones.scene);
      expect(layout.crop, 36);
      expect(layout.scale, 1);
      expect(layout.compact, isFalse);
    });

    test('a taller room grows the wall: seats keep their distance from the '
        'bottom', () {
      final layout = microOld(390, 452);
      expect(layout.crop, 0);
      expect(layout.scale, 1);
      expectPoint(layout.seats['A_m']!.face, const Point(176, 316), 'A_m');
    });

    test('the threshold is T + 764: under it, the compact profile', () {
      expect(minCompliantHeight(24), 788);
      expect(minCompliantHeight(36), 800);
      final at = TripZones(width: 360, height: 788, viewPaddingTop: 24);
      expect(at.profile, TripProfile.regular);
      final under = TripZones(width: 360, height: 787, viewPaddingTop: 24);
      expect(under.profile, TripProfile.compact);
      expect(microOld(360, under.scene).scale, 1);
    });

    test('compact: HUD 72, no gap, dashboard 226, scene H − T − 282', () {
      for (final (height, scene) in [(640.0, 334.0), (720.0, 414.0)]) {
        final zones = TripZones(width: 360, height: height, viewPaddingTop: 24);
        expect(zones.profile, TripProfile.compact, reason: '$height');
        expect(zones.hud, 72);
        expect(zones.gap, 0);
        expect(zones.dashboard, 226);
        expect(zones.overlap, 16);
        expect(zones.scene, scene, reason: '$height');
        expect(zones.sceneTop, 24 + 72);
        expect(zones.dashboardTop, height - 226);
      }
    });

    test('each profile fills the screen with its HUD and dashboard', () {
      for (final height in <double>[640, 720, 744, 787, 800, 844, 932]) {
        final zones = TripZones(width: 360, height: height, viewPaddingTop: 24);
        final compact = zones.profile == TripProfile.compact;
        expect(zones.hud, compact ? 72 : 114, reason: '$height');
        expect(zones.dashboard, compact ? 226 : 258, reason: '$height');
        expect(
          zones.inset +
              zones.hud +
              zones.gap +
              zones.scene +
              zones.dashboard -
              zones.overlap,
          closeTo(height, 1e-9),
        );
      }
    });

    test('over 430 wide the zones keep 390, centred', () {
      final wide = TripZones(width: 600, height: 844, viewPaddingTop: 36);
      expect(wide.width, 390);
      expect(wide.left, 105);
      final edge = TripZones(width: 430, height: 844, viewPaddingTop: 36);
      expect(edge.width, 430);
      expect(edge.left, 0);
      final narrow = TripZones(width: 320, height: 844, viewPaddingTop: 36);
      expect(narrow.width, 320);
      expect(narrow.left, 0);
    });
  });

  group('micro_old on the design frame, 390×444', () {
    final layout = microOld(390, 444);

    test('has every seat of the vehicle', () {
      expect(layout.seats.keys.toSet(), _table.keys.toSet());
      expect(layout.xFactor, 1);
    });

    test('face centres, rig scales and face widths', () {
      for (final MapEntry(key: id, value: row) in _table.entries) {
        final seat = layout.seats[id]!;
        expectPoint(seat.face, Point(row.x, row.y), id);
        expect(seat.rigScale, row.rig, reason: id);
        expect(seat.faceWidth, closeTo(84 * row.rig, 1e-9), reason: id);
      }
      expect(layout.seats['A_m']!.faceWidth, 84);
      expect(layout.seats['B_m']!.faceWidth, closeTo(67.2, 1e-9));
      expect(layout.seats['C_m']!.faceWidth, closeTo(52.5, 1e-9));
    });

    test('tags at face + (−38, +46) × rig scale, the front at (−32, +18)', () {
      for (final MapEntry(key: id, value: row) in _table.entries) {
        final seat = layout.seats[id]!;
        final offset = id == 'front_r'
            ? const Point(-32.0, 18.0)
            : Point(-38 * row.rig, 46 * row.rig);
        expectPoint(seat.tag, Point(row.x, row.y) + offset, '$id tag');
        expect(seat.tagSize, row.tag, reason: id);
      }
      // `C-Trip` box 26, the back-left tag: 24 at (90, 108).
      final c = layout.seats['C_l']!;
      expect(c.tag.x - c.tagSize / 2, closeTo(90, 0.5));
      expect(c.tag.y - c.tagSize / 2, closeTo(108, 1));
    });

    test('hit rects from the table', () {
      for (final MapEntry(key: id, value: row) in _table.entries) {
        final hit = _hits[id] ?? _hits[id[0]]!;
        expectRect(
          layout.seats[id]!.hit,
          Rectangle(row.x + hit.left, row.y + hit.top, hit.width, hit.height),
          id,
        );
      }
    });

    test('bubbles 8 pt above the head, notes at the hands', () {
      for (final MapEntry(key: id, value: row) in _table.entries) {
        final seat = layout.seats[id]!;
        expectPoint(
          seat.bubbleAnchor,
          Point(row.x, row.y - 42 * row.rig - 8),
          '$id bubble',
        );
        expectPoint(
          seat.tokenAnchor,
          Point(row.x, row.y + 50 * row.rig),
          '$id note',
        );
      }
    });

    test(
      "the driver's hand at (162, 398), the anchor of the driver's notes",
      () {
        expectPoint(layout.hand, const Point(162, 398), 'hand');
        expectPoint(layout.anchorOf(null), const Point(162, 398), 'driver');
      },
    );

    test("the front seat wins over A_r: its hit area is the design's", () {
      final front = layout.seats['front_r']!;
      final ar = layout.seats['A_r']!;
      expect(ar.hit.width, 100);
      expect(ar.hit.height, 80);
      expect(front.hit.width, 90);
      expect(overlaps(front.hit, ar.hit), isFalse);
      expectHitAreasApart(layout);
    });
  });

  group('tuktuk', () {
    test('one row at x 62, 195 and 328, scale 1.15', () {
      final layout = tuktuk(390, 444);
      expect(layout.seats.keys.toSet(), {'A_l', 'A_m', 'A_r'});
      for (final (id, x) in [('A_l', 62.0), ('A_m', 195.0), ('A_r', 328.0)]) {
        final seat = layout.seats[id]!;
        expectPoint(seat.face, Point(x, 308), id);
        expect(seat.rigScale, 1.15);
        expect(seat.faceWidth, closeTo(96.6, 1e-9));
        expect(seat.tagSize, 30);
        expectRect(seat.hit, Rectangle(x - 60, 308 - 52, 120, 120), id);
      }
      expectHitAreasApart(layout);
    });

    test('at 360 the hit areas narrow to the seat spacing', () {
      final layout = tuktuk(360, 420);
      const spacing = (195 - 62) * 360 / 390;
      for (final seat in layout.seats.values) {
        expect(seat.hit.width, lessThanOrEqualTo(spacing + 1e-9));
      }
      expectHitAreasApart(layout);
    });
  });

  group('width', () {
    test('x spreads by w/390; the front seat stays 40 from the end edge', () {
      final layout = microOld(360, 420);
      expect(layout.xFactor, closeTo(360 / 390, 1e-12));
      for (final MapEntry(key: id, value: row) in _table.entries) {
        final seat = layout.seats[id]!;
        final x = id == 'front_r' ? 320.0 : row.x * 360 / 390;
        expectPoint(seat.face, Point(x, row.y - 24), id);
        expect(seat.faceWidth, closeTo(84 * row.rig, 1e-9), reason: id);
      }
    });

    test('at 360 the back row narrows to 63.7, apart and at least 44', () {
      final layout = microOld(360, 420);
      for (final id in ['C_l', 'C_m', 'C_r']) {
        expect(
          layout.seats[id]!.hit.width,
          closeTo(69 * 360 / 390, 0.01),
          reason: id,
        );
      }
      expectHitAreasApart(layout);
      final front = layout.seats['front_r']!;
      expect(front.hit.width, 90);
      expect(front.hit.height, 80);
    });

    test('at 430 the seats spread wider and the front seat is at 390', () {
      final layout = microOld(430, 452);
      expect(layout.seats['front_r']!.face.x, 390);
      expect(layout.seats['A_m']!.face.x, closeTo(176 * 430 / 390, 1e-9));
      expectHitAreasApart(layout);
    });

    test('at 320 nothing overlaps and nothing is under 44', () {
      expectHitAreasApart(microOld(320, 420));
      expectHitAreasApart(tuktuk(320, 420));
    });
  });

  group('minimums', () {
    for (final (w, h) in [(390.0, 444.0), (360.0, 420.0)]) {
      for (final make in [microOld, tuktuk]) {
        test('${make == microOld ? 'micro_old' : 'tuktuk'} at $w×$h keeps '
            'every face size', () {
          final layout = make(w, h);
          for (final seat in layout.seats.values) {
            expect(
              seat.faceWidth,
              greaterThanOrEqualTo(seat.isNearRow ? nearFaceMin : backFaceMin),
              reason: seat.seatId,
            );
            expect(
              seat.face.y - seat.faceWidth / 2,
              greaterThanOrEqualTo(0),
              reason: '${seat.seatId} inside the scene',
            );
          }
          expectHitAreasApart(layout);
        });
      }
    }

    test('at 360×640 and 360×720 every face keeps its minimum', () {
      for (final height in <double>[640, 720]) {
        final zones = TripZones(width: 360, height: height, viewPaddingTop: 24);
        for (final make in [microOld, tuktuk]) {
          final layout = make(360, zones.scene);
          expect(layout.scale, 1);
          for (final seat in layout.seats.values) {
            expect(
              seat.faceWidth,
              greaterThanOrEqualTo(seat.isNearRow ? nearFaceMin : backFaceMin),
              reason: '${seat.seatId} at $height',
            );
            expect(seat.head.top, greaterThanOrEqualTo(0), reason: seat.seatId);
            expect(
              seat.head.bottom,
              lessThanOrEqualTo(layout.height),
              reason: '${seat.seatId} inside the scene',
            );
          }
          expectHitAreasApart(layout);
        }
      }
    });

    test('under a 334 scene the compact table scales; hit areas keep 44', () {
      final layout = microOld(360, 300);
      expect(layout.scale, closeTo(300 / 334, 1e-9));
      expect(layout.seats['A_m']!.faceWidth, lessThan(nearFaceMin));
      expectHitAreasApart(layout);
      for (final seat in layout.seats.values) {
        expect(seat.head.bottom, lessThanOrEqualTo(300), reason: seat.seatId);
      }
    });
  });

  // contracts/compact-trip-layout.md "Seats".
  group('compact', () {
    double x(String id, double width) =>
        id == 'front_r' ? width - 40 : _compact[id]!.x * width / 390;

    for (final width in <double>[360, 390]) {
      test('micro_old at a 334 scene, $width wide: the table', () {
        final layout = microOld(width, 334);
        expect(layout.compact, isTrue);
        expect(layout.scale, 1);
        expect(layout.seats.keys.toSet(), _compact.keys.toSet());
        for (final MapEntry(key: id, value: row) in _compact.entries) {
          final seat = layout.seats[id]!;
          expectPoint(seat.face, Point(x(id, width), row.y), id);
          expect(seat.rigScale, closeTo(row.rig, 1e-9), reason: id);
          expect(seat.tagSize, row.tag, reason: id);
        }
        expect(layout.seats['C_m']!.faceWidth, closeTo(50.4, 1e-9));
        expect(layout.seats['B_m']!.faceWidth, closeTo(55.44, 1e-9));
        expect(layout.seats['A_m']!.faceWidth, closeTo(80, 1e-9));
        expect(layout.seats['front_r']!.faceWidth, closeTo(80, 1e-9));
        expectPoint(layout.hand, Point(162 * width / 390, 290), 'hand');
        expectHitAreasApart(layout);
      });
    }

    test('at a 407 scene the table moves down by 73: more wall on top', () {
      final layout = microOld(360, 407);
      expect(layout.compact, isTrue);
      for (final MapEntry(key: id, value: row) in _compact.entries) {
        expectPoint(layout.seats[id]!.face, Point(x(id, 360), row.y + 73), id);
      }
      expectPoint(layout.hand, const Point(162 * 360 / 390, 363), 'hand');
      expectHitAreasApart(layout);
    });

    test('the tuktuk keeps its bench at scene − 136, scale 1.15', () {
      final layout = tuktuk(360, 334);
      for (final (id, x) in [('A_l', 62.0), ('A_m', 195.0), ('A_r', 328.0)]) {
        final seat = layout.seats[id]!;
        expectPoint(seat.face, Point(x * 360 / 390, 198), id);
        expect(seat.rigScale, 1.15);
      }
      expectHitAreasApart(layout);
    });

    test("hit rects are 008.5's times the scale ratio, narrowed to stay "
        'apart, the front seat whole', () {
      final layout = microOld(390, 334);
      final c = layout.seats['C_m']!;
      expect(c.hit.width, closeTo(68 * 0.6 / 0.625, 0.01));
      final front = layout.seats['front_r']!;
      expect(front.hit.width, closeTo(90 * 80 / 84, 0.01));
      expect(front.hit.height, closeTo(80 * 80 / 84, 0.01));
      expect(overlaps(front.hit, layout.seats['A_r']!.hit), isFalse);
      expectHitAreasApart(layout);
    });

    test('tags, bubbles and notes follow the compact rig scales', () {
      final layout = microOld(390, 334);
      for (final MapEntry(key: id, value: row) in _compact.entries) {
        final seat = layout.seats[id]!;
        final face = seat.face;
        final offset = id == 'front_r'
            ? const Point(-32.0, 18.0)
            : Point(-38 * row.rig, 46 * row.rig);
        expectPoint(seat.tag, face + offset, '$id tag');
        expectPoint(
          seat.bubbleAnchor,
          Point(face.x, max(10, face.y - 42 * row.rig - 8)),
          '$id bubble',
        );
        expectPoint(
          seat.tokenAnchor,
          Point(face.x, face.y + 50 * row.rig),
          '$id note',
        );
      }
    });

    test('a bench keeps its distance from its row', () {
      final regular = microOld(390, 444);
      expect(
        regular.placeOnRow(SeatRow.c, 88, 104),
        regular.place(88, 104),
        reason: "008.5's table: the design's place",
      );
      final compact = microOld(390, 334);
      // The back bench sits 12 under its row's faces, as on the design.
      expect(compact.placeOnRow(SeatRow.c, 88, 104).y, closeTo(46 + 12, 1e-9));
      expect(compact.placeOnRow(SeatRow.b, 46, 212).y, closeTo(122 + 16, 1e-9));
      expect(compact.placeOnRow(SeatRow.a, 6, 326).y, closeTo(206 + 18, 1e-9));
    });
  });

  group('tokens', () {
    test("the seat table's constants equal LayoutTokens.trip*", () {
      for (final (row, spec) in [
        (SeatRow.c, LayoutTokens.tripBack),
        (SeatRow.b, LayoutTokens.tripMiddle),
        (SeatRow.a, LayoutTokens.tripNear),
      ]) {
        final ours = microOldRows[row]!;
        expect(ours.rigScale, spec.scale, reason: '$row scale');
        expect(ours.y, spec.y, reason: '$row y');
        expect(ours.x, spec.x, reason: '$row x');
        expect(ours.tag, spec.tag, reason: '$row tag');
      }
      expect(designSceneWidth - frontFromEnd, LayoutTokens.tripFront.dx);
      expect(microOldFrontY, LayoutTokens.tripFront.dy);
      expect(driverHand.x, LayoutTokens.tripDriverHand.dx);
      expect(driverHand.y, LayoutTokens.tripDriverHand.dy);
      expect(tripHudHeight, LayoutTokens.tripHud);
      expect(designSceneWidth, LayoutTokens.tripSceneW);
      expect(designSceneHeight, LayoutTokens.tripSceneH);
      expect(dashboardHeight, LayoutTokens.tripDashboardH);
      expect(dashboardOverlap, LayoutTokens.tripDashboardOverlap);
      expect(minTouch, LayoutTokens.touchMin);
    });
  });
}
