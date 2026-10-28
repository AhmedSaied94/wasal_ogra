import 'dart:ui' show SemanticsAction;

import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/core/theme/components/app_icon.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/trip/presentation/dashboard/boosters_locked_bar.dart';
import 'package:wassal/features/trip/presentation/dashboard/boosters_row.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

import '../../../helpers/content.dart';
import '../../../helpers/design_component.dart';
import '../../../helpers/economy.dart';
import '../../../helpers/trip.dart';
import '../../../helpers/tutorial_content.dart';

// The locked boosters bar (M07 contracts/coach.md "The locked boosters
// bar", `Tutorial` boxes 48–49): its look, a label and not a button, and
// in the trip until the tutorial is done, with no booster control.

Future<void> _tutorialTrip(
  WidgetTester tester, {
  required bool newPlayer,
  DigitStyle digits = DigitStyle.arabicIndic,
}) async {
  await pumpTrip(
    tester,
    tripId: 'line_hay.02',
    digits: digits,
    newPlayer: newPlayer,
    economy: await testEconomy(content: tutorialContent()),
    content: contentTestOverrides(assets: tutorialBundledAssets()),
  );
  advanceMs(controllerOf(tester), 500);
  await tester.pump();
}

void main() {
  testWidgets('44 tall, r 14, dashboard.raised; the lock and the text, '
      'centred', (tester) async {
    await pumpDesignComponent(
      tester,
      const SizedBox(width: 366, child: BoostersLockedBar()),
    );
    final bar = find.byType(BoostersLockedBar);
    expect(tester.getSize(bar), const Size(366, 44));
    final box = tester.widget<DecoratedBox>(
      find.descendant(of: bar, matching: find.byType(DecoratedBox)).first,
    );
    final decoration = box.decoration as BoxDecoration;
    expect(decoration.color, ColorTokens.dashboardRaised);
    expect(
      decoration.borderRadius,
      const BorderRadius.all(Radius.circular(RadiusTokens.tray)),
    );
    final icon = tester.widget<AppIcon>(find.byType(AppIcon));
    expect(icon.name, 'lock');
    expect(icon.size, 16);
    expect(icon.color, ColorTokens.dashboardMuted);
    final l10n = AppLocalizations.of(tester.element(bar));
    final text = find.text(l10n.tripBoostersLocked);
    expect(text, findsOneWidget);
    expect(tester.widget<Text>(text).style?.color, ColorTokens.dashboardMuted);
    // Centred as one row: the gap from the bar's edges is the same.
    final bounds = tester.getRect(bar);
    final row = tester
        .getRect(find.byType(AppIcon))
        .expandToInclude(tester.getRect(text));
    expect(row.left - bounds.left, closeTo(bounds.right - row.right, 1));
    expect(row.center.dy, closeTo(bounds.center.dy, 1));
  });

  testWidgets('a label, not a button', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpDesignComponent(
      tester,
      const SizedBox(width: 366, child: BoostersLockedBar()),
    );
    final l10n = AppLocalizations.of(
      tester.element(find.byType(BoostersLockedBar)),
    );
    final node = tester.getSemantics(find.byType(BoostersLockedBar));
    expect(node.label, l10n.tripBoostersLocked);
    final data = node.getSemanticsData();
    expect(data.hasAction(SemanticsAction.tap), isFalse);
    expect(data.flagsCollection.isButton, isFalse);
    semantics.dispose();
  });

  for (final digits in DigitStyle.values) {
    testWidgets('a tutorial trip: the bar, and no booster control '
        '(${digits.name})', (tester) async {
      await _tutorialTrip(tester, newPlayer: true, digits: digits);
      expect(find.byType(BoostersLockedBar), findsOneWidget);
      expect(find.byType(BoostersRow), findsNothing);
      for (final b in BoosterId.values) {
        expect(find.byKey(BoostersRow.slotKey(b)), findsNothing);
      }
    });
  }

  testWidgets('the tutorial done: the boosters', (tester) async {
    await _tutorialTrip(tester, newPlayer: false);
    expect(find.byType(BoostersLockedBar), findsNothing);
    expect(find.byType(BoostersRow), findsOneWidget);
  });
}
