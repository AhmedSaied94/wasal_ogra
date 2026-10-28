import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/components/overlays.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/onboarding/onboarding_providers.dart';
import 'package:wassal/features/onboarding/presentation/name_sheet.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

import '../../../helpers/economy.dart';
import '../../../helpers/pump_app.dart';
import '../../../helpers/trip.dart';

// The Name sheet (contracts/name.md "The re-ask"): the Name card's content
// in a sheet, with the refused line when the server refused the last name;
// «تمام» records a new name and closes it, and it closes as every sheet
// does.

/// The seed whose first suggestion is the pool's first name, «حمادة».
const _seed = 24;

Future<TestEconomy> _open(WidgetTester tester, {bool refused = false}) async {
  final economy = await testEconomy();
  await pumpWassalApp(
    tester,
    economy: economyOverridesOf(economy),
    overrides: [nameSeedProvider.overrideWithValue(_seed)],
  );
  expect(currentLocation(tester), '/home');
  unawaited(showNameSheet(appContext(tester), refused: refused));
  await tester.pumpAndSettle();
  expect(find.byType(NameSheet), findsOneWidget);
  return economy;
}

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(appContext(tester));

String _field(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).controller!.text;

void main() {
  testWidgets('titled as the card, a fresh suggestion in the field', (
    tester,
  ) async {
    await _open(tester);
    expect(
      find.descendant(
        of: find.byType(AppSheet),
        matching: find.text(_l10n(tester).nameTitle),
      ),
      findsOneWidget,
    );
    expect(_field(tester), 'حمادة');
    expect(find.text(_l10n(tester).nameRefusedLine), findsNothing);
  });

  testWidgets('the refused line, above the field, in danger ink', (
    tester,
  ) async {
    await _open(tester, refused: true);
    final line = find.text(_l10n(tester).nameRefusedLine);
    expect(line, findsOneWidget);
    expect(
      tester.getRect(line).bottom,
      lessThanOrEqualTo(tester.getRect(find.byType(TextField)).top),
    );
    final style = tester.widget<Text>(line).style!;
    expect(style.color, ColorTokens.dangerInk);
    expect(style.fontSize, 14);
    expect(style.fontWeight, FontWeight.w600);
  });

  testWidgets('«تمام» records a new name and closes', (tester) async {
    final economy = await _open(tester, refused: true);
    final before = await opCount(economy, 'settings_update');
    await tester.tap(find.byKey(NameSheet.ctaKey));
    await tester.pumpAndSettle();
    expect(await opCount(economy, 'settings_update'), before + 1);
    expect(economy.service.view.displayName, 'حمادة');
    expect(find.byType(NameSheet), findsNothing);
  });

  group('closes, recording nothing:', () {
    Future<void> closed(WidgetTester tester, TestEconomy economy) async {
      await tester.pumpAndSettle();
      expect(find.byType(NameSheet), findsNothing);
      expect(await opCount(economy, 'settings_update'), 0);
      expect(currentLocation(tester), '/home');
    }

    testWidgets('✕', (tester) async {
      final economy = await _open(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(AppSheet),
          matching: find.bySemanticsLabel(_l10n(tester).closeLabel),
        ),
      );
      await closed(tester, economy);
    });

    testWidgets('a drag down', (tester) async {
      final economy = await _open(tester);
      await tester.fling(
        find.byKey(AppSheet.grabberKey),
        const Offset(0, 300),
        AppSheet.flingVelocity * 2,
      );
      await closed(tester, economy);
    });

    testWidgets('back', (tester) async {
      final economy = await _open(tester);
      await tester.binding.handlePopRoute();
      await closed(tester, economy);
    });

    testWidgets('the scrim', (tester) async {
      final economy = await _open(tester);
      await tester.tapAt(const Offset(195, 40));
      await closed(tester, economy);
    });
  });
}
