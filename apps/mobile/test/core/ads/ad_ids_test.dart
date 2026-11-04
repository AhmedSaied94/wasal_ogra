// The ad ids of each flavor (specs/018-m11-ads, contracts/platform-config.md
// "Ad ids", T002). Staging and prod's Android must hold the owner's ids
// (T065); their iOS waits for the iOS release.
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
    test("$flavor's Android holds none of the sample publisher (T065)", () {
      final ids = adIds[flavor]!;
      for (final id in [ids.androidAppId, ...ids.androidUnits.values]) {
        expect(id, isNot(contains(samplePublisher)), reason: id);
      }
    });

    test('$flavor gives each Android placement its own unit', () {
      final units = adIds[flavor]!.androidUnits.values;
      expect(units.toSet(), hasLength(units.length));
    });

    // iOS hasn't launched, so it may keep Google's sample ids (the owner's
    // decision, 2026-11-04). All or none: once any real id lands, the whole
    // column must be real, one unit per placement. Real ids before the iOS
    // release are on docs/owner-actions.md's list.
    test('$flavor\'s iOS is all samples, or all real with its own units', () {
      final ids = adIds[flavor]!;
      final column = [ids.iosAppId, ...ids.iosUnits.values];
      if (column.any((id) => id.contains(samplePublisher))) {
        for (final id in column) {
          expect(id, contains(samplePublisher), reason: id);
        }
        return;
      }
      final units = ids.iosUnits.values;
      expect(units.toSet(), hasLength(units.length));
    });
  }
}
