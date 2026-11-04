import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/bootstrap/ads_overrides.dart';
import 'package:wassal/core/ads/ads_providers.dart';
import 'package:wassal/core/ads/ads_service.dart';

// The app's scope wires the ads' warm-up (specs/018-m11-ads, review H1);
// without it the refill offer could stay «not ready» with nothing loading it.
// It wires Settings' privacy row too (T081); without that, a European player
// could never get back to the consent form.

final class _RequiresPrivacy implements AdsService {
  @override
  Future<bool> privacyOptionsRequired() async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

void main() {
  test('the default does nothing; the app takes the live one', () {
    final tests = ProviderContainer();
    addTearDown(tests.dispose);
    expect(tests.read(adWarmUpProvider), same(noAdWarmUp));

    final app = ProviderContainer(overrides: adsOverrides());
    addTearDown(app.dispose);
    expect(app.read(adWarmUpProvider), isNot(same(noAdWarmUp)));
  });

  test('the privacy row: no by default; the app asks the service', () async {
    final tests = ProviderContainer();
    addTearDown(tests.dispose);
    expect(await tests.read(adPrivacyRequiredProvider.future), isFalse);

    final app = ProviderContainer(
      overrides: [
        ...adsOverrides(),
        adsServiceProvider.overrideWithValue(_RequiresPrivacy()),
      ],
    );
    addTearDown(app.dispose);
    expect(await app.read(adPrivacyRequiredProvider.future), isTrue);
  });
}
