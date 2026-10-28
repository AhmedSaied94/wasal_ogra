import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/content/content_controller.dart';
import 'package:wassal/core/content/content_providers.dart';
import 'package:wassal/core/content/decode_pack_file.dart';
import 'package:wassal/core/theme/components/buttons.dart';
import 'package:wassal/core/theme/components/containers.dart';
import 'package:wassal/features/onboarding/data/drift_first_session_store.dart';
import 'package:wassal/features/onboarding/onboarding_providers.dart';
import 'package:wassal/features/onboarding/presentation/name_screen.dart';

import '../../../helpers/content.dart';
import '../../../helpers/economy.dart';
import '../../../helpers/pump_app.dart';
import '../../../helpers/routing.dart';
import '../../../helpers/trip.dart';
import '../../../helpers/tutorial_content.dart';

// The Name card (specs/012-m07-onboarding/contracts/name.md "The Name
// card"): a new player with the opening done, offline.

/// The seed whose first suggestion is the pool's first name, «حمادة».
const _seed = 24;

Future<TestEconomy> _pumpName(
  WidgetTester tester, {
  bool opening = true,
}) async {
  final economy = await testEconomy();
  if (opening) await DriftFirstSessionStore(economy.db).markOpeningDone(5);
  await pumpWassalApp(
    tester,
    newPlayer: true,
    economy: economyOverridesOf(economy),
    content: opening
        ? null
        : contentTestOverrides(assets: noSessionScenesAssets()),
    overrides: [nameSeedProvider.overrideWithValue(_seed)],
  );
  expect(currentLocation(tester), '/onboarding/name');
  return economy;
}

String _field(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).controller!.text;

bool _ctaEnabled(WidgetTester tester) =>
    tester.widget<AppButton>(find.byKey(NameScreen.ctaKey)).enabled;

Future<List<Map<String, Object?>>> _nameOps(TestEconomy economy) async => [
  for (final row in await economy.db.select(economy.db.ledgerOps).get())
    if (row.opType == 'settings_update')
      (jsonDecode(row.payload) as Map<String, dynamic>).cast<String, Object?>(),
];

void main() {
  testWidgets('the field holds the seeded suggestion; the dice changes it, '
      'never to the same', (tester) async {
    await _pumpName(tester);
    expect(_field(tester), 'حمادة');
    var showing = _field(tester);
    for (var i = 0; i < 10; i++) {
      await tester.tap(find.byKey(NameScreen.diceKey));
      await tester.pumpAndSettle();
      expect(_field(tester), isNot(showing));
      expect(_field(tester), isNotEmpty);
      showing = _field(tester);
    }
    expect(_ctaEnabled(tester), isTrue);
  });

  testWidgets('«تمام» is disabled for a name the rules refuse', (tester) async {
    await _pumpName(tester);
    for (final bad in ['', '   ', 'ح', '١٢٣', '12', 'حما‏دة']) {
      await tester.enterText(find.byType(TextField), bad);
      await tester.pump();
      expect(_ctaEnabled(tester), isFalse, reason: jsonEncode(bad));
    }
    await tester.enterText(find.byType(TextField), 'سيد');
    await tester.pump();
    expect(_ctaEnabled(tester), isTrue);
  });

  testWidgets('the field stops at 16', (tester) async {
    await _pumpName(tester);
    await tester.enterText(find.byType(TextField), 'ابتثجحخدذرزسشصضطظ');
    await tester.pump();
    expect(_field(tester).characters.length, 16);
  });

  testWidgets('«تمام» records one settings_update with the normalized name '
      'and goes to trip 1, offline', (tester) async {
    final economy = await _pumpName(tester);
    await tester.enterText(find.byType(TextField), '  حمادة   الصغير ');
    await tester.pump();
    await tester.tap(find.byKey(NameScreen.ctaKey));
    await tester.pumpAndSettle();
    expect(await _nameOps(economy), [
      {'display_name': 'حمادة الصغير'},
    ]);
    expect(economy.service.view.displayName, 'حمادة الصغير');
    expect(currentLocation(tester), '/trip/line_hay.01');
  });

  testWidgets('a pack that got ready meanwhile is taken before trip 1, and '
      'trip 1 is its own', (tester) async {
    await _pumpName(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(NameScreen)),
    );
    // v2 has no line_hay.01, so its tutorial starts at line_hay.02: trip 1
    // must come from the pack the switch made active.
    final json = samplePackJson();
    final pack = encodePackFile({
      ...json,
      'version': 2,
      'trips': [
        for (final trip
            in (json['trips']! as List).cast<Map<String, Object?>>())
          if (trip['trip_id'] != 'line_hay.01') trip,
      ],
    });
    final decoded = decodePackFile(pack.bytes, pack.expected) as PackDecoded;
    container.read(activeContentProvider.notifier).acceptReady(decoded.source);
    expect(container.read(contentVersionProvider), 1);

    await tester.tap(find.byKey(NameScreen.ctaKey));
    await tester.pumpAndSettle();
    expect(container.read(contentVersionProvider), 2);
    expect(currentLocation(tester), '/trip/line_hay.02');
  });

  testWidgets("the keyboard's done key acts like «تمام»", (tester) async {
    final economy = await _pumpName(tester);
    await tester.showKeyboard(find.byType(TextField));
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(await _nameOps(economy), [
      {'display_name': 'حمادة'},
    ]);
    expect(currentLocation(tester), '/trip/line_hay.01');
  });

  testWidgets('the done key does nothing for a refused name', (tester) async {
    final economy = await _pumpName(tester);
    await tester.enterText(find.byType(TextField), ' ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(await _nameOps(economy), isEmpty);
    expect(currentLocation(tester), '/onboarding/name');
  });

  testWidgets('back does nothing', (tester) async {
    await _pumpName(tester);
    await pressBack(tester);
    expect(currentLocation(tester), '/onboarding/name');
    expect(find.byType(NameScreen), findsOneWidget);
  });

  testWidgets('with the keyboard up, the whole card stays visible', (
    tester,
  ) async {
    await _pumpName(tester);
    const keyboard = 336.0;
    tester.view.viewInsets = const FakeViewPadding(bottom: keyboard);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    final card = tester.getRect(find.byType(AppCard));
    final avatar = tester.getRect(find.byKey(NameScreen.avatarKey));
    final screen = tester.getRect(find.byType(NameScreen));
    expect(avatar.top, greaterThanOrEqualTo(screen.top));
    expect(card.bottom, lessThanOrEqualTo(screen.bottom - keyboard));
    expect(
      tester.getRect(find.byKey(NameScreen.ctaKey)).bottom,
      lessThanOrEqualTo(screen.bottom - keyboard),
    );
  });

  testWidgets('with no opening scene, opening the Name card writes step 1', (
    tester,
  ) async {
    final economy = await _pumpName(tester, opening: false);
    expect((await DriftFirstSessionStore(economy.db).read()).stepReached, 1);
  });
}
