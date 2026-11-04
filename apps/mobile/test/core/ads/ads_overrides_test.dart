import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/bootstrap/ads_overrides.dart';
import 'package:wassal/core/ads/ads_providers.dart';

// The app's scope wires the ads' warm-up (specs/018-m11-ads, review H1);
// without it the refill offer could stay «not ready» with nothing loading it.

void main() {
  test('the default does nothing; the app takes the live one', () {
    final tests = ProviderContainer();
    addTearDown(tests.dispose);
    expect(tests.read(adWarmUpProvider), same(noAdWarmUp));

    final app = ProviderContainer(overrides: adsOverrides());
    addTearDown(app.dispose);
    expect(app.read(adWarmUpProvider), isNot(same(noAdWarmUp)));
  });
}
