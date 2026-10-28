import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/core/theme/components/containers.dart';
import 'package:wassal/core/theme/components/controls.dart';
import 'package:wassal/features/settings/settings_screen.dart';

import '../../helpers/pump_app.dart';

// Settings in the new look (spec FR-017): the digit style is a primary
// `Segmented` under its `ListRow`, in a card, and a choice applies
// everywhere at once. settings_screen_test.dart keeps M03's behaviour.

void main() {
  testWidgets('the digit style is a primary Segmented in a ListRow card', (
    tester,
  ) async {
    await pumpWassalApp(tester, initialLocation: '/settings');
    final segmented = find.byType(Segmented<DigitStyle>);
    expect(segmented, findsOne);
    expect(
      tester.widget<Segmented<DigitStyle>>(segmented).style,
      SegmentedStyle.primary,
    );
    // As the Settings artboard draws it: the row's title over the control,
    // in one card.
    final card = find.ancestor(of: segmented, matching: find.byType(AppCard));
    expect(card, findsOne);
    expect(find.descendant(of: card, matching: find.byType(ListRow)), findsOne);
    expect(find.byType(ScreenHeader), findsOne);
  });

  testWidgets('Western applies on settings and on Home at once', (
    tester,
  ) async {
    await pumpWassalApp(tester, initialLocation: '/settings');
    expect(find.textContaining('١٬٢٥٠'), findsWidgets);
    await tester.tap(find.byKey(SettingsScreen.optionKey(DigitStyle.western)));
    await tester.pump();
    expect(find.textContaining('1,250'), findsWidgets);
    expect(find.textContaining('١٬٢٥٠'), findsNothing);

    // Opened on its own, so its back control goes to الموقف.
    await tester.tap(find.bySemanticsLabel('رجوع'));
    await tester.pumpAndSettle();
    expect(currentLocation(tester), '/home');
    // Home's tank.
    expect(find.textContaining('5/5'), findsWidgets);
  });
}
