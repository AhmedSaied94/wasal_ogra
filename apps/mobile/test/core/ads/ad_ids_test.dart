// The ad ids of each flavor (specs/018-m11-ads, contracts/platform-config.md
// "Ad ids", T002). Staging and prod fail until the owner's ids land (T065):
// that failure is the merge gate.
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/bootstrap/flavor.dart';
import 'package:wassal/core/ads/ad_ids.dart';
import 'package:wassal/core/ads/ads_gateway.dart';

Iterable<String> _all(AdIds ids) => [
  ids.androidAppId,
  ids.iosAppId,
  ...ids.androidUnits.values,
  ...ids.iosUnits.values,
];

void main() {
  test('every flavor maps every unit on both platforms', () {
    for (final flavor in Flavor.values) {
      final ids = adIds[flavor]!;
      expect(
        ids.androidUnits.keys.toSet(),
        AdUnit.values.toSet(),
        reason: '$flavor',
      );
      expect(
        ids.iosUnits.keys.toSet(),
        AdUnit.values.toSet(),
        reason: '$flavor',
      );
      for (final id in _all(ids)) {
        expect(id, startsWith('ca-app-pub-'), reason: '$flavor');
      }
    }
  });

  test('app ids use "~", units use "/"', () {
    for (final flavor in Flavor.values) {
      final ids = adIds[flavor]!;
      expect(ids.androidAppId, contains('~'));
      expect(ids.iosAppId, contains('~'));
      for (final unit in [...ids.androidUnits.values, ...ids.iosUnits.values]) {
        expect(unit, contains('/'), reason: '$flavor');
      }
    }
  });

  test("dev holds only Google's sample publisher", () {
    for (final id in _all(adIds[Flavor.dev]!)) {
      expect(id, contains(samplePublisher));
    }
  });

  for (final flavor in [Flavor.staging, Flavor.prod]) {
    test("$flavor holds none of the sample publisher (owner's ids, T065)", () {
      for (final id in _all(adIds[flavor]!)) {
        expect(id, isNot(contains(samplePublisher)), reason: id);
      }
    });

    test('$flavor gives each placement its own unit', () {
      final ids = adIds[flavor]!;
      for (final units in [ids.androidUnits, ids.iosUnits]) {
        expect(units.values.toSet(), hasLength(units.length));
      }
    });
  }
}
