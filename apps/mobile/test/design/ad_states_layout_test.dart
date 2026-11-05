import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/features/fuel/presentation/fuel_refill_ad_offer.dart';
import 'package:wassal/features/trip/presentation/cards/booster_card.dart';

import 'design_check.dart';
import 'samples/ad_states.dart';

// M11's trip-screen boards against their measured boxes (specs/018-m11-ads,
// T064, contracts/design-briefs.md "As drawn"): `BoosterAdCard` (the ad
// box 35, the buy box 39, «مش دلوقتي» box 43), and `NoFuelAd` /
// `NoFuelAdLimit` (the ad tile box 13, the BONAT tile box 17, «البنزين»
// box 21 and «ارجع الموقف» box 22). The boards label a two-line button
// with its lines joined by «، », as the app does.

void main() {
  testWidgets('BoosterAdCard: the boxes', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpBoosterAdCard(tester);
    expectLayoutMatches(tester, 'BoosterAdCard');
    expect(find.byKey(BoosterCard.adKey), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('NoFuelAd: the boxes', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpNoFuelAd(tester);
    expectLayoutMatches(tester, 'NoFuelAd');
    expect(find.byKey(FuelRefillAdOffer.adKey), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('NoFuelAdLimit: the boxes', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpNoFuelAd(tester, refillsToday: 3);
    expectLayoutMatches(tester, 'NoFuelAdLimit');
    semantics.dispose();
  });
}
