import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show Key;
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/core/l10n/number_formatter.dart';
import 'package:wassal/core/theme/components/buttons.dart';
import 'package:wassal/features/trip/application/trip_phase.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';
import 'package:wassal/features/trip/presentation/cards/booster_card.dart';
import 'package:wassal/features/trip/presentation/cards/failure_card.dart';
import 'package:wassal/features/trip/presentation/dashboard/boosters_row.dart';
import 'package:wassal/features/trip/presentation/dashboard/dashboard.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

import '../../../design/samples/c_trip.dart';
import '../../../design/samples/fail.dart';
import '../../../design/samples/trip_events.dart';
import '../../../helpers/trip.dart';

// The trip's ad buttons (specs/018-m11-ads, US2, T038): the failure card's
// «صالح الركاب» above the BONAT revive, the «زحمة» card's «زحمة ببلاش»
// above «اشتري واستعمل», and the dashboard's «إعلان» badge.

const _numbers = NumberFormatter(DigitStyle.arabicIndic);

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(TripDashboard)));

Future<void> _show(WidgetTester tester, TripModel model) async {
  await pumpTrip(tester, tripId: cTripId);
  controllerOf(tester).debugShowModel(model);
  await tester.pumpAndSettle();
}

RewardedAdButton _button(WidgetTester tester, Key key) =>
    tester.widget<RewardedAdButton>(find.byKey(key));

TripModel _jamCard(AdSlot ad) => TripModel(
  phase: TripPhase.boosterCard,
  view: cTripView(phase: TripPhase.boosterCard),
  boosterCard: BoosterCardModel(
    booster: BoosterId.trafficJam,
    priceBonat: 8,
    bonat: 45,
    shortBy: null,
    ad: ad,
  ),
);

void main() {
  group('FailureCard', () {
    testWidgets('ready: «صالح الركاب» in the ad slot, above the revive', (
      tester,
    ) async {
      await _show(tester, failModel());
      final l10n = _l10n(tester);
      final ad = _button(tester, FailureCard.adSlotKey);
      expect(ad.ready, isTrue);
      expect(ad.title, l10n.reviveAdTitle);
      expect(ad.benefit, l10n.reviveAdBenefit(_numbers.integer(40)));
      final slot = tester.getRect(find.byKey(FailureCard.adSlotKey));
      final revive = tester.getRect(find.byKey(FailureCard.reviveKey));
      expect(slot.bottom, lessThanOrEqualTo(revive.top));
      expect(slot.height, greaterThanOrEqualTo(44));
    });

    testWidgets('not ready', (tester) async {
      await _show(tester, failModel(reviveAd: AdSlot.notReady));
      expect(_button(tester, FailureCard.adSlotKey).ready, isFalse);
      expect(find.text(_l10n(tester).adNotReady), findsOneWidget);
    });

    testWidgets('offline', (tester) async {
      await _show(tester, failModel(reviveAd: AdSlot.offline));
      expect(_button(tester, FailureCard.adSlotKey).ready, isFalse);
      expect(find.text(_l10n(tester).adNeedsNetwork), findsOneWidget);
    });

    testWidgets('hidden: the room stays, with no button', (tester) async {
      await _show(tester, failModel(reviveAd: AdSlot.hidden));
      expect(find.byType(RewardedAdButton), findsNothing);
      expect(find.byKey(FailureCard.adSlotKey), findsOneWidget);
      expect(find.byKey(FailureCard.reviveKey), findsOneWidget);
    });
  });

  group('BoosterCard', () {
    testWidgets('«زحمة ببلاش» above «اشتري واستعمل»', (tester) async {
      await _show(tester, _jamCard(AdSlot.ready));
      final l10n = _l10n(tester);
      final ad = _button(tester, BoosterCard.adKey);
      expect(ad.ready, isTrue);
      expect(ad.title, l10n.trafficJamAdTitle);
      expect(ad.benefit, l10n.trafficJamAdBenefit(_numbers.integer(10)));
      final adRect = tester.getRect(find.byKey(BoosterCard.adKey));
      final buy = tester.getRect(find.byKey(BoosterCard.buyKey));
      expect(adRect.bottom, lessThanOrEqualTo(buy.top));
      expect(adRect.height, greaterThanOrEqualTo(44));
      expect(buy.height, greaterThanOrEqualTo(44));
    });

    testWidgets('not ready: drawn disabled', (tester) async {
      await _show(tester, _jamCard(AdSlot.notReady));
      expect(_button(tester, BoosterCard.adKey).ready, isFalse);
    });

    testWidgets('hidden: none, and the purchase as before', (tester) async {
      await _show(tester, _jamCard(AdSlot.hidden));
      expect(find.byKey(BoosterCard.adKey), findsNothing);
      expect(find.byKey(BoosterCard.buyKey), findsOneWidget);
    });
  });

  testWidgets('BoostersRow: «إعلان» on «زحمة» when its ad is on offer', (
    tester,
  ) async {
    await pumpTripEvents(tester);
    final l10n = _l10n(tester);
    final slot = find.byKey(BoostersRow.slotKey(BoosterId.trafficJam));
    expect(
      find.descendant(of: slot, matching: find.text(l10n.trafficJamAdBadge)),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: slot,
        matching: find.text(l10n.tripBoosterPriceBadge(_numbers.integer(5))),
      ),
      findsNothing,
    );
  });
}
