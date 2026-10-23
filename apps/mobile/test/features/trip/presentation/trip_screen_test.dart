import 'package:flame/game.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/economy/domain/economy_state.dart';
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/core/l10n/number_formatter.dart';
import 'package:wassal/features/trip/application/trip_phase.dart';
import 'package:wassal/features/trip/domain/scene_layout.dart';
import 'package:wassal/features/trip/presentation/cards/no_fuel_card.dart';
import 'package:wassal/features/trip/presentation/dashboard/dashboard.dart';
import 'package:wassal/features/trip/presentation/dashboard/tray.dart';
import 'package:wassal/features/trip/presentation/overlays/hit_areas.dart';
import 'package:wassal/features/trip/presentation/overlays/token_layer.dart';
import 'package:wassal/features/trip/presentation/scene/trip_game.dart';
import 'package:wassal/features/trip/presentation/top_bar/top_bar.dart';
import 'package:wassal/features/trip/presentation/trip_screen.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

import '../../../helpers/economy.dart';
import '../../../helpers/pump_app.dart';
import '../../../helpers/trip.dart';

// The trip screen's bands, system bars, scaling and overlays (tasks.md
// T033, contracts/scene-layout.md).

/// Words that would tell who has paid (FR-033).
const _paymentWords = ['دفع', 'دافع', 'لسه', 'باقي', 'فلوس', 'أجرة'];

/// The system UI modes the screen asks for, in order.
List<Object?> systemModes(WidgetTester tester) {
  final modes = <Object?>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'SystemChrome.setEnabledSystemUIMode') {
        modes.add(call.arguments);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return modes;
}

/// What a screen reader visits, in order.
List<String> heard(WidgetTester tester) => [
  for (final node in tester.semantics.simulatedAccessibilityTraversal())
    if (node.label.isNotEmpty) node.label,
];

/// The zones on the reference frame, with its top inset.
TripZones referenceZones() => TripZones(
  width: 390,
  height: 844,
  viewPaddingTop: TripSurface.reference.inset,
);

void main() {
  // 008.5 (M21) moved the zones to the design's (contracts/trip-layout.md):
  // the HUD under the top inset, the gap, the scene, and 258 over 16.
  testWidgets('the zones at 390×844: the HUD, the scene, 258 over 16', (
    tester,
  ) async {
    await pumpTrip(tester);
    final zones = referenceZones();
    final top = tester.getRect(find.byType(TripHud));
    final scene = tester.getRect(find.byType(GameWidget<TripGame>));
    final dashboard = tester.getRect(find.byType(TripDashboard));
    expect(top.top, zones.inset);
    expect(top.height, tripHudHeight);
    expect(dashboard.height, dashboardHeight);
    expect(dashboard.bottom, 844);
    expect(scene.top, zones.sceneTop);
    expect(scene.height, zones.scene);
    expect(scene.bottom - dashboard.top, dashboardOverlap);
  });

  testWidgets('the system bars hide on entry and come back on exit', (
    tester,
  ) async {
    final modes = systemModes(tester);
    await pumpTrip(tester);
    expect(modes, [SystemUiMode.immersiveSticky.toString()]);
    // Leaving: the pause, then «ارجع الموقف».
    controllerOf(tester).pause(PauseReason.button);
    await tester.pumpAndSettle();
    await tester.tap(find.text('ارجع الموقف'));
    await tester.pumpAndSettle();
    expect(find.byType(TripScreen), findsNothing);
    expect(modes.last, SystemUiMode.edgeToEdge.toString());
  });

  testWidgets('sent on to the unfinished trip, the bars stay hidden', (
    tester,
  ) async {
    final economy = await testEconomy();
    await testController(economy).open('line_hay.02');
    final modes = systemModes(tester);
    await pumpTrip(tester, economy: economy);
    expect(currentLocation(tester), '/trip/line_hay.02');
    expect(find.byType(TripScreen), findsOneWidget);
    expect(modes.last, SystemUiMode.immersiveSticky.toString());
  });

  testWidgets('a card hides the trip under it from the screen reader', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpTrip(tester);
    final pause = lookupAppLocalizations(const Locale('ar')).tripTopBarPause;
    expect(heard(tester), contains(pause));
    controllerOf(tester).pause(PauseReason.button);
    await tester.pumpAndSettle();
    final labels = heard(tester);
    expect(labels, contains('ارجع الموقف'));
    expect(labels, isNot(contains(pause)));
    expect(labels.where((l) => l.contains('×')), isEmpty, reason: 'the drawer');
    semantics.dispose();
  });

  testWidgets('text scale is clamped to 1.3', (tester) async {
    await pumpTrip(tester, textScale: 2);
    final context = tester.element(find.byType(TripDashboard));
    expect(MediaQuery.textScalerOf(context).scale(10), 13);
  });

  testWidgets('tokens sit where the layout and the alpha put them', (
    tester,
  ) async {
    await pumpTrip(tester);
    final c = controllerOf(tester);
    for (
      var i = 0;
      i < 2000 && c.view!.tokens.every((t) => t.hopMs == 0);
      i++
    ) {
      advanceMs(c, 33);
    }
    final zones = referenceZones();
    final layout = SceneLayout(
      c.session!.facts.definition.seats,
      vehicle: c.session!.facts.definition.vehicleId,
      width: 390,
      height: zones.scene,
    );

    Future<void> check() async {
      await tester.pump();
      final token = c.view!.tokens.firstWhere((t) => t.hopMs > 0);
      final at = tokenPosition(token, layout, c.alpha);
      final chip = tester.getCenter(
        find.descendant(
          of: find.byType(TokenLayer),
          matching: find.byKey(ValueKey(token.tokenId)),
        ),
      );
      expect(chip.dx, closeTo(at.dx, 0.01));
      expect(chip.dy, closeTo(at.dy + zones.sceneTop, 0.01));
    }

    expect(c.alpha, 0);
    await check();
    // Half a step: the token moves on between engine steps.
    c.advance(const Duration(milliseconds: 16));
    expect(c.alpha, greaterThan(0));
    await check();
  });

  // 008.5 (M21): the design's notes say their amount at 16; 15 stays the
  // floor.
  testWidgets('a token is at least 40×24 with a 15 pt amount', (tester) async {
    await pumpTrip(tester);
    final c = controllerOf(tester);
    for (var i = 0; i < 2000 && c.view!.tokens.isEmpty; i++) {
      advanceMs(c, 33);
    }
    await tester.pump();
    final chip = find.byType(MoneyNote).first;
    final size = tester.getSize(chip);
    expect(size.width, greaterThanOrEqualTo(tokenMinWidth));
    expect(size.height, greaterThanOrEqualTo(tokenMinHeight));
    final text = tester.widget<Text>(
      find.descendant(of: chip, matching: find.byType(Text)),
    );
    expect(text.style!.fontSize, greaterThanOrEqualTo(15));
  });

  testWidgets('passenger areas name the seat and the station, not payment', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpTrip(tester, tripId: 'line_gamaa.02');
    final c = controllerOf(tester);
    advanceMs(c, 5000);
    await tester.pump();
    final seated = c.view!.passengers;
    expect(seated, isNotEmpty);
    for (final p in seated) {
      final area = find.byKey(HitAreas.keyOf(p.passengerId));
      expect(area, findsOneWidget);
      final rect = tester.getRect(area);
      expect(rect.width, greaterThanOrEqualTo(minTouch));
      expect(rect.height, greaterThanOrEqualTo(minTouch));
      final label = tester.getSemantics(area).label;
      final letter = const ['أ', 'ب', 'ج', 'د'][p.slot!];
      expect(label, contains(letter));
      expect(label, anyOf(contains('الصف'), contains('الكرسي')));
      for (final word in _paymentWords) {
        expect(label, isNot(contains(word)), reason: label);
      }
    }
    semantics.dispose();
  });

  testWidgets('drawer slots are buttons that say their amount and count', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpTrip(tester, digits: DigitStyle.western);
    final label = tester.getSemantics(find.byKey(Tray.slotKey(500))).label;
    expect(label, contains('5'));
    semantics.dispose();
  });

  group('the no-fuel card', () {
    Future<TestEconomy> emptyTank() => testEconomy(
      firstState: (nowMs) => EconomyState.newPlayer(
        fuelMax: 5,
        nowMs: nowMs,
      ).copyWith(fuel: FuelState(liters: 0, countedFromMs: nowMs)),
    );

    testWidgets('counts down to the next liter', (tester) async {
      final economy = await emptyTank();
      await pumpTrip(tester, economy: economy, settle: false);
      expect(controllerOf(tester).phase, TripPhase.noFuel);
      expect(find.byType(NoFuelCard), findsOneWidget);
      expect(find.text('البنزين خلص'), findsOneWidget);
      final next = controllerOf(tester).model.nextLiterAtMs!;
      String shown() =>
          'لتر جديد بعد ${const NumberFormatter(DigitStyle.arabicIndic).countdown(Duration(milliseconds: next - economy.clock.nowMs()))}';
      expect(find.text(shown()), findsOneWidget);
      economy.passTime(const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text(shown()), findsOneWidget);
    });

    testWidgets('goes to the fuel sheet', (tester) async {
      await pumpTrip(tester, economy: await emptyTank(), settle: false);
      await tester.tap(find.text('هات بنزين'));
      await pumpFrames(tester);
      expect(currentLocation(tester), '/shop/fuel');
    });

    testWidgets('goes back to the stand', (tester) async {
      await pumpTrip(tester, economy: await emptyTank(), settle: false);
      await tester.tap(find.text('ارجع الموقف'));
      await pumpFrames(tester);
      expect(currentLocation(tester), '/home');
    });
  });
}
