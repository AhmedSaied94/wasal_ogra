import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/ads/ads_providers.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/settings/settings_screen.dart';

import '../../helpers/fake_ads_gateway.dart';
import '../../helpers/pump_app.dart';

// Settings' way back to the consent form (specs/018-m11-ads, T081): the
// row shows only where Google requires it, so Egypt never sees it, and it
// opens the privacy options form.

Future<void> _pump(WidgetTester tester, FakeAdsGateway gateway) async {
  await pumpWassalApp(
    tester,
    initialLocation: '/settings',
    overrides: [
      adsGatewayProvider.overrideWithValue(gateway),
      adPrivacyRequiredProvider.overrideWith(liveAdPrivacyRequired),
    ],
  );
  await tester.pump();
  await tester.pump();
}

final _row = find.byKey(SettingsScreen.adPrivacyKey);

void main() {
  testWidgets('tests and samples keep the row out, with no ad call', (
    tester,
  ) async {
    final gateway = FakeAdsGateway();
    await pumpWassalApp(
      tester,
      initialLocation: '/settings',
      overrides: [adsGatewayProvider.overrideWithValue(gateway)],
    );
    await tester.pump();
    expect(_row, findsNothing);
    expect(gateway.calls, isEmpty);
  });

  testWidgets('not required: no row', (tester) async {
    final gateway = FakeAdsGateway();
    await _pump(tester, gateway);
    expect(gateway.count('privacyOptionsRequired'), 1);
    expect(_row, findsNothing);
  });

  testWidgets('required: the row opens the form', (tester) async {
    final gateway = FakeAdsGateway()..privacyRequired = true;
    await _pump(tester, gateway);
    expect(find.text('خصوصية الإعلانات'), findsOneWidget);

    await tester.tap(_row);
    await tester.pump();
    await tester.pump();
    expect(gateway.count('showPrivacyOptions'), 1);
    expect(find.text('محتاج نت'), findsNothing);
  });

  testWidgets('a form that cannot show says so', (tester) async {
    final gateway = FakeAdsGateway()
      ..privacyRequired = true
      ..privacyFormShows = false;
    await _pump(tester, gateway);

    await tester.tap(_row);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('محتاج نت'), findsOneWidget);

    await tester.pump(MotionTokens.toastHold);
    await tester.pump(const Duration(seconds: 1));
  });
}
