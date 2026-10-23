import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/features/trip/domain/scene_layout.dart';

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

bool inside(Rectangle<double> outer, Point<double> p) =>
    p.x >= outer.left &&
    p.x <= outer.right &&
    p.y >= outer.top &&
    p.y <= outer.bottom;

bool overlaps(Rectangle<double> a, Rectangle<double> b) {
  final i = a.intersection(b);
  return i != null && i.width > 0.001 && i.height > 0.001;
}

void main() {
  const vehicles = ['tuktuk', 'micro_old'];
  const compliant = [(390.0, 520.0), (360.0, 456.0), (360.0, 420.0)];

  for (final vehicle in vehicles) {
    for (final (w, h) in compliant) {
      test('$vehicle at $w×$h keeps every minimum', () {
        final layout = SceneLayout(seatsOf(vehicle), width: w, height: h);
        final all = layout.seats.values.toList();
        expect(all, hasLength(seatsOf(vehicle).length));
        for (final seat in all) {
          final min = seat.isNearRow ? nearFaceMin : backFaceMin;
          expect(
            seat.face.width,
            greaterThanOrEqualTo(min),
            reason: seat.seatId,
          );
          expect(seat.hit.width, greaterThanOrEqualTo(minTouch));
          expect(seat.hit.height, greaterThanOrEqualTo(minTouch));
          expect(
            layout.bounds.containsRectangle(seat.face),
            isTrue,
            reason: '${seat.seatId} ${seat.face}',
          );
          expect(inside(layout.bounds, seat.bubbleAnchor), isTrue);
          expect(inside(layout.bounds, seat.tokenAnchor), isTrue);
        }
        for (var i = 0; i < all.length; i++) {
          for (var j = i + 1; j < all.length; j++) {
            expect(
              overlaps(all[i].hit, all[j].hit),
              isFalse,
              reason: '${all[i].seatId} and ${all[j].seatId}',
            );
          }
        }
      });
    }
  }

  test("the front seat's hit area wins over A_r's, which keeps 44×44", () {
    final layout = SceneLayout(seatsOf('micro_old'), width: 390, height: 520);
    final front = layout.seats['front_r']!;
    final ar = layout.seats['A_r']!;
    expect(overlaps(front.face, ar.face), isTrue);
    expect(overlaps(front.hit, ar.hit), isFalse);
    expect(ar.hit.height, greaterThanOrEqualTo(minTouch));
    expect(front.hit.bottom, greaterThan(ar.hit.bottom));
  });

  test('columns run r, m, l from the viewer right', () {
    final layout = SceneLayout(seatsOf('tuktuk'), width: 390, height: 520);
    final r = layout.seats['A_r']!.face.left;
    final m = layout.seats['A_m']!.face.left;
    final l = layout.seats['A_l']!.face.left;
    expect(r, greaterThan(m));
    expect(m, greaterThan(l));
  });

  test('farther rows are smaller and higher', () {
    final layout = SceneLayout(seatsOf('micro_old'), width: 390, height: 520);
    final a = layout.seats['A_m']!.face;
    final b = layout.seats['B_m']!.face;
    final c = layout.seats['C_m']!.face;
    expect(a.width, greaterThan(b.width));
    expect(b.width, greaterThan(c.width));
    expect(a.top, greaterThan(b.top));
    expect(b.top, greaterThan(c.top));
  });

  test('a 360×640 screen shrinks faces but keeps hit areas', () {
    final scene = bandHeights(640).scene;
    expect(scene, 316);
    final layout = SceneLayout(seatsOf('micro_old'), width: 360, height: scene);
    expect(layout.seats['A_m']!.face.width, lessThan(nearFaceMin));
    for (final seat in layout.seats.values) {
      expect(seat.hit.width, greaterThanOrEqualTo(minTouch));
      expect(seat.hit.height, greaterThanOrEqualTo(minTouch));
    }
  });

  test('bands: top 110 plus inset, dashboard 230, overlap 16', () {
    final bands = bandHeights(844, topInset: 24);
    expect(bands.top, 134);
    expect(bands.dashboard, 230);
    expect(bands.overlap, 16);
    expect(bands.scene, 844 - 134 - 230 + 16);
    expect(bandHeights(744).scene, compliantSceneHeight);
  });
}
