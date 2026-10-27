import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wassal/core/platform/store_launcher.dart';

// The update card's store link (specs/011-m06-identity-sync, contracts/
// server-states.md "`StoreLauncher`", research R18).

final class _Launches {
  final calls = <(Uri, LaunchMode)>[];
  bool answer = true;
  Object? error;

  Future<bool> call(
    Uri url, {
    LaunchMode mode = LaunchMode.platformDefault,
  }) async {
    calls.add((url, mode));
    if (error case final e?) throw e;
    return answer;
  }
}

void main() {
  for (final id in [
    'com.wassalogra.app',
    'com.wassalogra.app.dev',
    'com.wassalogra.app.staging',
  ]) {
    test('Android opens the Play listing of $id, outside the app', () async {
      final launches = _Launches();
      final launcher = UrlStoreLauncher(
        packageName: id,
        platform: TargetPlatform.android,
        launch: launches.call,
      );

      expect(launcher.hasListing, isTrue);
      expect(await launcher.openListing(), isTrue);

      final (url, mode) = launches.calls.single;
      expect(
        url.toString(),
        'https://play.google.com/store/apps/details?id=$id',
      );
      expect(mode, LaunchMode.externalApplication);
    });
  }

  test('iOS has no listing while the App Store id is empty', () async {
    expect(iosAppStoreId, isEmpty);
    final launches = _Launches();
    final launcher = UrlStoreLauncher(
      packageName: 'com.wassalogra.app',
      platform: TargetPlatform.iOS,
      launch: launches.call,
    );

    expect(launcher.hasListing, isFalse);
    expect(await launcher.openListing(), isFalse);
    expect(launches.calls, isEmpty);
  });

  test('iOS opens the App Store once the id is set', () async {
    final launches = _Launches();
    final launcher = UrlStoreLauncher(
      packageName: 'com.wassalogra.app',
      platform: TargetPlatform.iOS,
      appStoreId: '1234567890',
      launch: launches.call,
    );

    expect(await launcher.openListing(), isTrue);
    expect(
      launches.calls.single.$1.toString(),
      'https://apps.apple.com/app/id1234567890',
    );
  });

  test('no package name, no listing', () {
    expect(
      UrlStoreLauncher(
        packageName: '',
        platform: TargetPlatform.android,
      ).hasListing,
      isFalse,
    );
  });

  test('a launch that fails or throws answers false', () async {
    final launches = _Launches()..answer = false;
    final launcher = UrlStoreLauncher(
      packageName: 'com.wassalogra.app',
      platform: TargetPlatform.android,
      launch: launches.call,
    );
    expect(await launcher.openListing(), isFalse);

    launches.error = PlatformException(code: 'ACTIVITY_NOT_FOUND');
    expect(await launcher.openListing(), isFalse);
  });
}
