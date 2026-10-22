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
