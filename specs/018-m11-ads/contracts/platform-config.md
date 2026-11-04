# Contract: Platform Configuration

## Dependencies (`apps/mobile/pubspec.yaml`)

| Package | Version | Why |
| --- | --- | --- |
| `google_mobile_ads` | ^9.2.0 | ads, UMP, request configuration (research R1). A Swift Package on iOS |
| `gma_mediation_applovin` | ^2.6.4 | mediation (R2). A Swift Package |
| `gma_mediation_unity` | ^1.11.0 | mediation (R2). A Swift Package |

There is still no Podfile. A CI step fails if `ios/Podfile` appears.

## Ad ids (`lib/core/ads/ad_ids.dart`, research R4)

```dart
/// The AdMob ids of each flavor. Not secrets: every build ships them.
const Map<Flavor, AdIds> adIds = { … };

final class AdIds {
  final String androidAppId;
  final Map<AdUnit, String> androidUnits;
  final String iosAppId;
  final Map<AdUnit, String> iosUnits;
}
```

- **dev:** Google's sample ids:
  - app ids: `ca-app-pub-3940256099942544~3347511713` (Android), `~1458002511` (iOS);
  - rewarded units: `/5224354917` (Android), `/1712485313` (iOS);
  - interstitial units: `/1033173712` (Android), `/4411468910` (iOS).
- **staging and prod:** the owner's ids (owner action before the staging check). The real unit of
  `morningPiggy` is the one in `ADS_ALLOWED_AD_UNITS` on that host (B07).
- A test checks that every flavor maps every `AdUnit`, that dev holds only Google's sample
  publisher (`3940256099942544`), and that staging and prod's Android hold none of it.
- **iOS for now (owner's decision, 2026-11-04):** staging and prod's iOS keep the sample ids until
  iOS launches. The test accepts a column that is all samples or all real, never a mix.

## Android

- `android/app/build.gradle.kts`: each product flavor sets
  `manifestPlaceholders["admobAppId"]` to its app id. A Gradle check keeps it equal to
  `ad_ids.dart`, the way the flavor's API host is checked.
- `AndroidManifest.xml`:
  `<meta-data android:name="com.google.android.gms.ads.APPLICATION_ID" android:value="${admobAppId}"/>`.
  The SDK's `AD_ID` permission comes from the SDK's own manifest. Play Console's data-safety and ads
  declarations are owner actions.
- The plain-HTTP guard is unchanged: the SDK uses HTTPS.

## iOS

- `Info.plist`:
  - `GADApplicationIdentifier = $(ADMOB_APP_ID)`, with each scheme's configurations setting
    `ADMOB_APP_ID`;
  - `NSUserTrackingUsageDescription` (Arabic, from the owner; English fallback in `InfoPlist.strings`);
  - Google's `SKAdNetworkItems` list, plus AppLovin's and Unity's.
- The ATT prompt comes from UMP's IDFA message, which the owner turns on in AdMob → Privacy &
  messaging (research R6).
- `codemagic.yaml`'s unsigned dev IPA builds with the dev ids.

## Request configuration (research R5)

Set once in `GmaAdsGateway.start`, before `MobileAds.instance.initialize()`:

```text
maxAdContentRating:            T
tagForChildDirectedTreatment:  no
tagForUnderAgeOfConsent:       no
testDeviceIds:                 [] (staging uses the AdMob console's test devices)
```

## Docs this feature edits

- mobile §24.3 → resolved (R2); mobile §15.1 → the gateway's real API (contracts/ads-gateway.md),
  the consent order, `ad_reward_seen` from the economy, and the wallet through the sync pass.
- backend §22.8 → resolved (R5). The constitution's "all-ages limits until the store age rating is
  decided" now has its decision (13+). The game's own content keeps the product spec's limits, so
  no amendment is needed.
- `specs/008-m02-trip-screen/contracts/trip-controller.md` "Ads" → `isOffered` at any time (R7).
- `apps/mobile/CLAUDE.md`: what M11 has, the commands, the widened ad-SDK guard.
