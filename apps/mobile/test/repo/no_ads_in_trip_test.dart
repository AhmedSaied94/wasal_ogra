import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_source.dart';

// No ad SDK call may run while a trip runs (constitution IX). The trip screen
// never reaches an ad SDK at all: M11's offers come through `TripAdOffers`,
// which the trip asks only while the engine is paused or failed
// (specs/008-m02-trip-screen, research R20).
const _trip = 'lib/features/trip/';

final _adImport = RegExp(
  r'''^[ \t]*(?:import|export)\s+['"](package:google_mobile_ads/[^'"]*|package:wassal/core/ads/[^'"]*)['"]''',
  multiLine: true,
);

/// The ad SDK and its mediation adapters.
final _sdkImport = RegExp(
  r'''^[ \t]*(?:import|export)\s+['"](package:(?:google_mobile_ads|gma_mediation_[a-z_]+)/[^'"]*)['"]''',
  multiLine: true,
);

/// Where the SDK may be imported (specs/018-m11-ads, research R3): the
/// gateway, and the bootstrap for adapter registration.
bool sdkAllowedIn(String path) =>
    path == 'lib/core/ads/gma_ads_gateway.dart' ||
    path.startsWith('lib/bootstrap/');

/// The SDK imports in [source], one line each.
List<String> sdkImports(String source) => [
  for (final match in _sdkImport.allMatches(stripComments(source))) match[1]!,
];

/// The ad imports in [source], one line each.
List<String> adImports(String source) => [
  for (final match in _adImport.allMatches(stripComments(source))) match[1]!,
];

void main() {
  test('no file of the trip screen imports an ad SDK or core/ads', () {
    final files = libDartFiles().where(
      (f) => f.path.replaceAll(r'\', '/').startsWith(_trip),
    );
    expect(files, isNotEmpty, reason: '$_trip must exist');
    final violations = [
      for (final file in files)
        for (final hit in adImports(file.readAsStringSync()))
          '${file.path}: $hit',
    ];
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test('only the gateway and the bootstrap import the ad SDK', () {
    final violations = [
      for (final file in libDartFiles())
        if (!sdkAllowedIn(file.path.replaceAll(r'\', '/')))
          for (final hit in sdkImports(file.readAsStringSync()))
            '${file.path}: $hit',
    ];
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test('the SDK scan catches the SDK and the adapters only', () {
    expect(
      sdkImports("import 'package:google_mobile_ads/google_mobile_ads.dart';"),
      hasLength(1),
    );
    expect(
      sdkImports(
        "import 'package:gma_mediation_applovin/gma_mediation_applovin.dart';",
      ),
      hasLength(1),
    );
    expect(
      sdkImports("import 'package:wassal/core/ads/ads_gateway.dart';"),
      isEmpty,
    );
    expect(sdkAllowedIn('lib/core/ads/gma_ads_gateway.dart'), isTrue);
    expect(sdkAllowedIn('lib/core/ads/ads_service.dart'), isFalse);
    expect(sdkAllowedIn('lib/features/result/presentation/x.dart'), isFalse);
  });

  test('the scan catches ad imports and ignores the rest', () {
    expect(
      adImports("import 'package:google_mobile_ads/google_mobile_ads.dart';"),
      hasLength(1),
    );
    expect(
      adImports("export 'package:wassal/core/ads/ads_gateway.dart';"),
      hasLength(1),
    );
    expect(
      adImports(
        "// import 'package:google_mobile_ads/google_mobile_ads.dart';",
      ),
      isEmpty,
    );
    expect(
      adImports(
        "import 'package:wassal/features/trip/application/trip_ad_offers.dart';",
      ),
      isEmpty,
    );
  });
}
