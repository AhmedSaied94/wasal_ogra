// The AdMob ids of each flavor (specs/018-m11-ads, research R4,
// contracts/platform-config.md "Ad ids"). Not secrets: every build ships
// them. The app ids are also in each flavor's Android manifest placeholder
// (`android/app/build.gradle.kts`) and iOS build setting (`ADMOB_APP_ID`);
// `test/repo/admob_app_id_test.dart` keeps them equal to this table.
import 'package:wassal/bootstrap/flavor.dart';
import 'package:wassal/core/ads/ads_gateway.dart' show AdUnit;

final class AdIds {
  const AdIds({
    required this.androidAppId,
    required this.androidUnits,
    required this.iosAppId,
    required this.iosUnits,
  });

  final String androidAppId;
  final Map<AdUnit, String> androidUnits;
  final String iosAppId;
  final Map<AdUnit, String> iosUnits;
}

/// Google's sample publisher: test ads only.
const samplePublisher = '3940256099942544';

const _sampleAndroidRewarded = 'ca-app-pub-$samplePublisher/5224354917';
const _sampleIosRewarded = 'ca-app-pub-$samplePublisher/1712485313';

/// Google's sample ids. Every rewarded placement shares the sample rewarded
/// unit; the piggy's server check can't reach a laptop, so dev signs it with
/// `ads_dev_callback` (B07 quickstart §2).
const _sample = AdIds(
  androidAppId: 'ca-app-pub-$samplePublisher~3347511713',
  androidUnits: {
    AdUnit.resultDouble: _sampleAndroidRewarded,
    AdUnit.fuelRefill: _sampleAndroidRewarded,
    AdUnit.tripRevive: _sampleAndroidRewarded,
    AdUnit.trafficJam: _sampleAndroidRewarded,
    AdUnit.morningPiggy: _sampleAndroidRewarded,
    AdUnit.interstitial: 'ca-app-pub-$samplePublisher/1033173712',
  },
  iosAppId: 'ca-app-pub-$samplePublisher~1458002511',
  iosUnits: {
    AdUnit.resultDouble: _sampleIosRewarded,
    AdUnit.fuelRefill: _sampleIosRewarded,
    AdUnit.tripRevive: _sampleIosRewarded,
    AdUnit.trafficJam: _sampleIosRewarded,
    AdUnit.morningPiggy: _sampleIosRewarded,
    AdUnit.interstitial: 'ca-app-pub-$samplePublisher/4411468910',
  },
);

const Map<Flavor, AdIds> adIds = {
  Flavor.dev: _sample,
  // Owner action T065: the owner's real ids (one rewarded unit per placement, the
  // piggy's on B07's `ADS_ALLOWED_AD_UNITS`, and one interstitial). Until
  // then staging and prod hold the sample ids, which
  // `test/core/ads/ad_ids_test.dart` refuses, so the PR can't merge.
  Flavor.staging: _sample,
  Flavor.prod: _sample,
};
