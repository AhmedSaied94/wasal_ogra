// The store listing, for the update card (specs/011-m06-identity-sync,
// contracts/server-states.md "`StoreLauncher`", research R18): the Play
// Store app on Android, the App Store once the listing exists.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wassal/core/platform/app_info.dart';

part 'store_launcher.g.dart';

/// The App Store listing's id. Empty until the owner creates the listing
/// (docs/owner-actions.md, M06): until then the update card has no button
/// on iOS, and still blocks when forced.
const iosAppStoreId = '';

abstract interface class StoreLauncher {
  /// False on iOS while [iosAppStoreId] is empty.
  bool get hasListing;

  /// Opens the listing outside the app. False when it couldn't.
  Future<bool> openListing();
}

/// `url_launcher`'s `launchUrl`, or a test's.
typedef UrlLaunch = Future<bool> Function(Uri url, {LaunchMode mode});

final class UrlStoreLauncher implements StoreLauncher {
  UrlStoreLauncher({
    required this._packageName,
    required this._platform,
    this._appStoreId = iosAppStoreId,
    this._launch = launchUrl,
  });

  final String _packageName;
  final TargetPlatform _platform;
  final String _appStoreId;
  final UrlLaunch _launch;

  /// The listing's address, or null when there is none.
  Uri? get listing => switch (_platform) {
    TargetPlatform.android when _packageName.isNotEmpty => Uri.https(
      'play.google.com',
      '/store/apps/details',
      {'id': _packageName},
    ),
    TargetPlatform.iOS when _appStoreId.isNotEmpty => Uri.https(
      'apps.apple.com',
      '/app/id$_appStoreId',
    ),
    _ => null,
  };

  @override
  bool get hasListing => listing != null;

  @override
  Future<bool> openListing() async {
    final url = listing;
    if (url == null) return false;
    try {
      return await _launch(url, mode: LaunchMode.externalApplication);
    } on PlatformException {
      return false;
    }
  }
}

@Riverpod(keepAlive: true)
StoreLauncher storeLauncher(Ref ref) => UrlStoreLauncher(
  packageName: ref.watch(appInfoProvider).value?.packageName ?? '',
  platform: defaultTargetPlatform,
);
