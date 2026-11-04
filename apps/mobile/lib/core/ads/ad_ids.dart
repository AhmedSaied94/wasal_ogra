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

/// The owner's publisher (T065).
const _publisher = 'ca-app-pub-8517724530135268';

/// The owner's Android app, for staging and prod alike (T065).
const _androidAppId = '$_publisher~5907754524';

/// The owner's Android units (T065). Each flavor's piggy is the unit in its
/// host's `ADS_ALLOWED_AD_UNITS` (B07), with that host's SSV callback.
const _stagingAndroidUnits = {
  AdUnit.resultDouble: '$_publisher/5361562259',
  AdUnit.fuelRefill: '$_publisher/1389306469',
  AdUnit.tripRevive: '$_publisher/6483072230',
  AdUnit.trafficJam: '$_publisher/3038651249',
  AdUnit.morningPiggy: '$_publisher/2511736310',
  AdUnit.interstitial: '$_publisher/1318375468',
};

const _prodAndroidUnits = {
  AdUnit.resultDouble: '$_publisher/1266017530',
  AdUnit.fuelRefill: '$_publisher/7340471295',
  AdUnit.tripRevive: '$_publisher/3944538803',
  AdUnit.trafficJam: '$_publisher/3856908897',
  AdUnit.morningPiggy: '$_publisher/3908277141',
  AdUnit.interstitial: '$_publisher/7692212128',
};

const Map<Flavor, AdIds> adIds = {
  Flavor.dev: _sample,
  // iOS hasn't launched: its columns keep Google's samples, test ads only
  // (the owner's decision, 2026-11-04). The real ids are on
  // docs/owner-actions.md's list before the iOS release.
  Flavor.staging: AdIds(
    androidAppId: _androidAppId,
    androidUnits: _stagingAndroidUnits,
    iosAppId: 'ca-app-pub-$samplePublisher~1458002511',
    iosUnits: {
      AdUnit.resultDouble: _sampleIosRewarded,
      AdUnit.fuelRefill: _sampleIosRewarded,
      AdUnit.tripRevive: _sampleIosRewarded,
      AdUnit.trafficJam: _sampleIosRewarded,
      AdUnit.morningPiggy: _sampleIosRewarded,
      AdUnit.interstitial: 'ca-app-pub-$samplePublisher/4411468910',
    },
  ),
  Flavor.prod: AdIds(
    androidAppId: _androidAppId,
    androidUnits: _prodAndroidUnits,
    iosAppId: 'ca-app-pub-$samplePublisher~1458002511',
    iosUnits: {
      AdUnit.resultDouble: _sampleIosRewarded,
      AdUnit.fuelRefill: _sampleIosRewarded,
      AdUnit.tripRevive: _sampleIosRewarded,
      AdUnit.trafficJam: _sampleIosRewarded,
      AdUnit.morningPiggy: _sampleIosRewarded,
      AdUnit.interstitial: 'ca-app-pub-$samplePublisher/4411468910',
    },
  ),
};
