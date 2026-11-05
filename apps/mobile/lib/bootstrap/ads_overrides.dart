// M11's overrides of the seams M02 and M08 left (specs/018-m11-ads,
// contracts/seams.md). The app's scope takes them; tests and the design
// samples keep their fakes unless they add these with a fake gateway
// (`adsGatewayProvider.overrideWithValue(FakeAdsGateway(...))`).
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:wassal/core/ads/ads_checkpoint.dart';
import 'package:wassal/core/ads/ads_providers.dart';
import 'package:wassal/core/ads/ads_trip_offers.dart';
import 'package:wassal/features/home/application/checkpoint.dart';
import 'package:wassal/features/home/application/home_slots.dart';
import 'package:wassal/features/home/application/piggy_banner_state.dart';
import 'package:wassal/features/home/presentation/piggy_banner.dart';
import 'package:wassal/features/result/application/result_slots.dart';
import 'package:wassal/features/result/presentation/result_double_offer.dart';
import 'package:wassal/features/trip/trip_providers.dart';

List<Override> adsOverrides() => [
  // What a card needs loaded on its way in.
  adWarmUpProvider.overrideWith(liveAdWarmUp),
  // Settings' row back to the consent form, where Google requires it.
  adPrivacyRequiredProvider.overrideWith(liveAdPrivacyRequired),
  // Consent, the preloads and the interstitial, before every start.
  betweenTripsCheckpointProvider.overrideWith(
    (ref) => AdsCheckpoint(ref.watch(adsServiceProvider)),
  ),
  // The result's ×2, under the pay.
  resultDoubleSlotProvider.overrideWithValue(
    (context, args) => ResultDoubleOffer(args: args),
  ),
  // The morning piggy under the savings card. Hidden from the start, the
  // street takes its space; hidden by this run's ad, the space stays, so the
  // cards don't move and its toast shows where the banner was.
  morningPiggySlotProvider.overrideWith(
    (ref) =>
        ref.watch(piggyBannerProvider) == PiggyBannerState.hidden &&
            ref.read(piggyServiceProvider).lastNonce.value == null
        ? null
        : (_) => const PiggyBanner(),
  ),
  // The failure card's revive and the «زحمة» card's ad.
  tripAdOffersProvider.overrideWith(
    (ref) => AdsTripOffers(ref.watch(adsServiceProvider)),
  ),
];
