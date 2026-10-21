import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/bootstrap/flavor.dart';
import 'package:wassal/core/network/api_environment.dart';

void main() {
  test('each flavor has its API base', () {
    expect(apiBaseUrl(Flavor.dev, devOverride: ''), 'http://localhost:8000');
    expect(
      apiBaseUrl(Flavor.dev, devOverride: 'http://10.0.2.2:8000'),
      'http://10.0.2.2:8000',
    );
    expect(
      apiBaseUrl(Flavor.staging, devOverride: 'http://10.0.2.2:8000'),
      'https://staging-api.141-147-129-92.sslip.io',
    );
    expect(
      apiBaseUrl(Flavor.prod, devOverride: 'http://10.0.2.2:8000'),
      'https://api.193-122-74-125.sslip.io',
    );
  });

  group('isAllowedUrl', () {
    bool allowed(Flavor flavor, String url) =>
        isAllowedUrl(flavor, Uri.parse(url));

    test('staging and prod allow only https', () {
      for (final flavor in [Flavor.staging, Flavor.prod]) {
        expect(
          allowed(flavor, 'https://api.example.com/packs/core-2.json.gz'),
          isTrue,
        );
        expect(allowed(flavor, 'http://localhost:8000/v1'), isFalse);
        expect(allowed(flavor, 'http://10.0.2.2:8000/v1'), isFalse);
        expect(allowed(flavor, 'http://127.0.0.1/v1'), isFalse);
      }
    });

    test('dev also allows http to the developer machine', () {
      expect(allowed(Flavor.dev, 'https://api.example.com/x'), isTrue);
      expect(allowed(Flavor.dev, 'http://localhost:8000/x'), isTrue);
      expect(allowed(Flavor.dev, 'http://127.0.0.1:8000/x'), isTrue);
      expect(allowed(Flavor.dev, 'http://10.0.2.2:8000/x'), isTrue);
      expect(allowed(Flavor.dev, 'http://example.com/x'), isFalse);
      expect(allowed(Flavor.dev, 'http://localhost.example.com/x'), isFalse);
    });

    test('other schemes and relative URLs are refused', () {
      for (final flavor in Flavor.values) {
        expect(allowed(flavor, 'ftp://localhost/x'), isFalse);
        expect(allowed(flavor, 'file:///data/x'), isFalse);
        expect(allowed(flavor, '/packs/core-2.json.gz'), isFalse);
        expect(allowed(flavor, 'https:///no-host'), isFalse);
      }
    });
  });
}
