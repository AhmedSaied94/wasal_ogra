import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// The player id reaches the ad network only as the piggy's server-side
// verification (specs/018-m11-ads, FR-026, T055): a scan of
// `lib/core/ads/` for where it is read and where the SDK's user id is set.

List<File> _adsSources() => [
  for (final entity in Directory('lib/core/ads').listSync(recursive: true))
    if (entity is File &&
        entity.path.endsWith('.dart') &&
        !entity.path.endsWith('.g.dart'))
      entity,
];

String _name(File file) => file.uri.pathSegments.last;

void main() {
  test('only the piggy reads the player id', () {
    final readers = {
      for (final file in _adsSources())
        if (RegExp(r'[pP]layerId\b').hasMatch(file.readAsStringSync()))
          _name(file),
    };
    // The provider hands it to the piggy; the piggy puts it in its
    // verification.
    expect(readers, {'ads_providers.dart', 'piggy_service.dart'});
  });

  test('the piggy puts it only in a PiggyVerification', () {
    final source = File('lib/core/ads/piggy_service.dart').readAsStringSync();
    final uses = RegExp(r'\b(player|_playerId)\b').allMatches(source).length;
    expect(uses, greaterThan(0));
    expect(RegExp(r'userId:\s*player\b').allMatches(source), hasLength(1));
    expect(source, contains('PiggyVerification('));
  });

  test('the SDK gets a user id only from the verification', () {
    final gateway = File('lib/core/ads/gma_ads_gateway.dart')
        .readAsStringSync();
    final setters = RegExp(r'userId:\s*([^,)\n]+)').allMatches(gateway);
    expect(setters, isNotEmpty);
    for (final setter in setters) {
      expect(setter.group(1)!.trim(), 'verification.userId');
    }
    for (final file in _adsSources()) {
      if (_name(file) == 'gma_ads_gateway.dart') continue;
      expect(
        file.readAsStringSync(),
        isNot(contains('ServerSideVerificationOptions')),
        reason: _name(file),
      );
    }
  });
}
