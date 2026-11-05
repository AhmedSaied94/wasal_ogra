import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';
import 'package:wassal/core/ads/ads_gateway.dart';
import 'package:wassal/core/ads/ads_providers.dart';
import 'package:wassal/core/economy/economy_providers.dart';
import 'package:wassal/core/sync/server_status.dart';
import 'package:wassal/features/result/presentation/result_double_offer.dart';

import '../../design/samples/result.dart';
import '../../helpers/fake_ads_gateway.dart';

// The result's ×2 (specs/018-m11-ads, US1, contracts/seams.md
// "`ResultDoubleOffer`", T033): its states, one ad doubling the pay once,
// and the decline. Failed, unpaid and tutorial trips 1–2 are `adOffer`'s
// Hidden (test/core/ads/ad_offer_test.dart, ads_service_test.dart), which
// draws nothing, as the doubled case here shows.

/// The board's result with the real offer over [gateway].
Future<ProviderContainer> _pump(
  WidgetTester tester,
  FakeAdsGateway gateway, {
  bool online = true,
  bool doubled = false,
}) async {
  final container = await pumpResult(
    tester,
    doubled: doubled,
    doubleOffer: null,
    // The sample's slot draws the real offer over the real service.
    overrides: [
      adsGatewayProvider.overrideWithValue(gateway),
      isOnlineProvider.overrideWithValue(online),
    ],
  );
  await container.read(adsServiceProvider).ensureReady();
  // The offer's rebuild, then the slot's.
  await tester.pump();
  await tester.pump();
  return container;
}

Finder get _offer => find.byKey(ResultDoubleOffer.offerKey);

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(_offer));

/// [n] as the app writes it.
String _n(ProviderContainer c, int n) =>
    c.read(numberFormatterProvider).integer(n);

/// A ×2 ad loaded earlier (the sample's player is before tutorial trip 3,
/// so nothing preloads on its own).
FakeAdsGateway _loaded() => FakeAdsGateway(ready: {AdUnit.resultDouble});

void main() {
  testWidgets('ready: «اقبض ×٢» over «+١٧٠ بدل ٨٥»', (tester) async {
    final c = await _pump(tester, _loaded());
    final l10n = _l10n(tester);
    final benefit = l10n.resultDoubleBenefit(_n(c, 170), _n(c, 85));
    expect(find.text('اقبض ×٢'), findsOneWidget);
    expect(find.text(benefit), findsOneWidget);
    expect(
      find.bySemanticsLabel(l10n.pairLabel('اقبض ×٢', benefit)),
      findsOneWidget,
    );
  });

  testWidgets('not ready, and offline', (tester) async {
    final gateway = FakeAdsGateway(loadsBecomeReady: false);
    await _pump(tester, gateway);
    expect(find.text('الإعلان مش جاهز'), findsOneWidget);
    expect(find.text('اقبض ×٢'), findsNothing);
  });

  testWidgets('offline says «محتاج نت»', (tester) async {
    await _pump(tester, _loaded(), online: false);
    expect(find.text('محتاج نت'), findsOneWidget);
  });

  testWidgets('a reward doubles the pay once, and the offer goes', (
    tester,
  ) async {
    final gateway = _loaded();
    final container = await _pump(tester, gateway);
    final before = container.read(economyViewProvider).jenehat;

    await tester.tap(_offer);
    await tester.pump();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(gateway.count('show', AdUnit.resultDouble), 1);
    expect(container.read(economyViewProvider).jenehat, before + 85);
    expect(container.read(economyViewProvider).lastResult!.doubled, isTrue);
    expect(_offer, findsNothing);
    expect(find.textContaining(_n(container, 170)), findsWidgets);
  });

  testWidgets('Closed changes nothing', (tester) async {
    final gateway = _loaded()..script(AdUnit.resultDouble, [const Closed()]);
    final container = await _pump(tester, gateway);
    final before = container.read(economyViewProvider).jenehat;
    await tester.tap(_offer);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(container.read(economyViewProvider).jenehat, before);
    expect(_offer, findsOneWidget);
  });

  testWidgets('hidden on a doubled result', (tester) async {
    await _pump(tester, _loaded(), doubled: true);
    expect(_offer, findsNothing);
  });

  testWidgets('the decline is ≥ 44×44 and hides the offer for this result', (
    tester,
  ) async {
    final c = await _pump(tester, _loaded());
    final decline = find.byKey(ResultDoubleOffer.declineKey);
    final size = tester.getSize(decline);
    expect(size.width, greaterThanOrEqualTo(44));
    expect(size.height, greaterThanOrEqualTo(44));
    expect(
      find.text(_l10n(tester).resultDoubleDecline(_n(c, 85))),
      findsOneWidget,
    );
    await tester.tap(decline);
    await tester.pump();
    expect(_offer, findsNothing);
  });
}
