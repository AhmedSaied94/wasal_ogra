// The AdMob app id of each flavor in the Android and iOS builds equals
// `lib/core/ads/ad_ids.dart` (specs/018-m11-ads, contracts/platform-config.md,
// T004, T005).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/bootstrap/flavor.dart';
import 'package:wassal/core/ads/ad_ids.dart';

const _gradle = 'android/app/build.gradle.kts';
const _manifest = 'android/app/src/main/AndroidManifest.xml';
const _plist = 'ios/Runner/Info.plist';
const _pbxproj = 'ios/Runner.xcodeproj/project.pbxproj';

/// The flavor of an Xcode configuration, by the display name it sets.
Flavor _flavorOfDisplayName(String name) => switch (name) {
  'وصّل dev' => Flavor.dev,
  'وصّل staging' => Flavor.staging,
  'وصّل الأجرة' => Flavor.prod,
  _ => throw StateError('Unknown display name $name'),
};

void main() {
  test("each Android flavor's placeholder is its app id", () {
    final gradle = File(_gradle).readAsStringSync();
    for (final flavor in Flavor.values) {
      final block = RegExp(
        'create\\("${flavor.name}"\\) \\{(.*?)\\n        \\}',
        dotAll: true,
      ).firstMatch(gradle);
      expect(block, isNotNull, reason: '$flavor');
      final id = RegExp(r'manifestPlaceholders\["admobAppId"\] = "([^"]+)"')
          .firstMatch(block![1]!);
      expect(id?[1], adIds[flavor]!.androidAppId, reason: '$flavor');
    }
  });

  test('the manifest reads the placeholder', () {
    final manifest = File(_manifest).readAsStringSync();
    expect(
      manifest,
      contains(
        'android:name="com.google.android.gms.ads.APPLICATION_ID"\n'
        r'            android:value="${admobAppId}"',
      ),
    );
  });

  test('Info.plist reads ADMOB_APP_ID and lists the ad networks', () {
    final plist = File(_plist).readAsStringSync();
    expect(
      plist,
      contains(
        '<key>GADApplicationIdentifier</key>\n\t\t<string>\$(ADMOB_APP_ID)',
      ),
    );
    expect(plist, contains('<key>NSUserTrackingUsageDescription</key>'));
    // Google's own network is in every list.
    expect(plist, contains('<string>cstr6suwn9.skadnetwork</string>'));
  });

  test("each Xcode configuration sets its flavor's iOS app id", () {
    final pbxproj = File(_pbxproj).readAsStringSync();
    final pairs = RegExp(
      r'APP_DISPLAY_NAME = "([^"]+)";\s*ADMOB_APP_ID = "([^"]+)";',
    ).allMatches(pbxproj).toList();
    // Debug, Release and Profile for each flavor, plus the base three.
    expect(pairs, hasLength(12));
    expect(
      RegExp('APP_DISPLAY_NAME =').allMatches(pbxproj),
      hasLength(pairs.length),
    );
    for (final pair in pairs) {
      final flavor = _flavorOfDisplayName(pair[1]!);
      expect(pair[2], adIds[flavor]!.iosAppId, reason: pair[1]);
    }
  });
}
