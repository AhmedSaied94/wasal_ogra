import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/features/trip/application/trip_controller.dart';
import 'package:wassal/features/trip/domain/scene_layout.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';
import 'package:wassal/features/trip/presentation/overlays/station_sign_name.dart';
import 'package:wassal/features/trip/presentation/scene/scene_space.dart';
import 'package:wassal/features/trip/presentation/scene/windows_component.dart';
import 'package:wassal/features/trip/presentation/trip_colors.dart';

import '../../../helpers/trip.dart';

// The next station's sign in the window carries its name (HANDOFF §11
// `C-Trip` "Next-station sign": «الكوبري», 13/700, centred on the board), in
// the station's letter colour, never under 12 pt, and moving with the board.

StationChip _next(TripController c) =>
    c.view!.strip.chips.firstWhere((chip) => chip.next);

SceneLayout _layoutOf(WidgetTester tester) =>
    tester.widget<StationSignName>(find.byType(StationSignName)).layout;

Future<TripController> _nearStop(WidgetTester tester, int countdownMs) async {
  await pumpTrip(tester);
  final c = controllerOf(tester);
  await untilView(tester, c, (view) {
    final left = view.strip.countdownMs;
    return left != null && left <= countdownMs;
  });
  return c;
}

void main() {
  testWidgets('no sign, and no name, until the last stretch', (tester) async {
    await pumpTrip(tester);
    final c = controllerOf(tester);
    expect(c.view!.strip.countdownMs, greaterThan(signLeadMs));
    expect(find.byKey(StationSignName.nameKey), findsNothing);
  });

  testWidgets("the name is on the board, in the station's letter colour", (
    tester,
  ) async {
    final c = await _nearStop(tester, signLeadMs ~/ 2);
    final next = _next(c);
    final name = find.byKey(StationSignName.nameKey);
    expect(tester.widget<Text>(name).data, next.name);
    expect(
      tester.widget<Text>(name).style!.color,
      TripColors.station(next.slot).letter,
    );
    final sign = stationSign(
      _layoutOf(tester),
      c.view!.strip.countdownMs,
      reduceMotion: false,
    )!;
    final scene = tester.getTopLeft(find.byType(StationSignName));
    final centre = tester.getCenter(name) - scene;
    expect(centre.dx, moreOrLessEquals(sign.board.center.dx, epsilon: 0.5));
    expect(centre.dy, moreOrLessEquals(sign.board.center.dy, epsilon: 0.5));
  });

  testWidgets('never under 12 pt, from the moment the sign shows', (
    tester,
  ) async {
    await _nearStop(tester, signLeadMs);
    final name = find.byKey(StationSignName.nameKey);
    expect(tester.widget<Text>(name).style!.fontSize, greaterThanOrEqualTo(12));
  });

  testWidgets('the sign slides in and grows, and stands still under '
      'reduced motion', (tester) async {
    await pumpTrip(tester);
    final layout = _layoutOf(tester);
    final atStop = stationSign(layout, 0, reduceMotion: false)!;
    final arriving = stationSign(layout, signLeadMs, reduceMotion: false)!;
    final still = stationSign(layout, signLeadMs, reduceMotion: true)!;

    // At the stop: the design's board, 76×30 at (10, 76) on the tuktuk's
    // windscreen's left, or the microbus's left window.
    expect(atStop.board.outerRect.size, layout.rectOf(0, 0, 76, 30).size);
    expect(atStop.scale, layout.scale);
    expect(arriving.board.center.dx, lessThan(atStop.board.center.dx));
    expect(arriving.board.width, lessThan(atStop.board.width));
    expect(
      DesignExtras.stationSignName.fontSize! * arriving.scale,
      greaterThanOrEqualTo(12),
    );
    expect(still.board, atStop.board);
    expect(stationSign(layout, signLeadMs + 1, reduceMotion: false), isNull);
    expect(stationSign(layout, null, reduceMotion: false), isNull);
  });
}
