import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'app_info.g.dart';

/// The running app's version and platform, as requests and pack checks
/// need them (specs/006-m04-content-loader/contracts/updates.md).
abstract interface class AppInfo {
  /// `MAJOR.MINOR.PATCH`.
  String get version;

  /// The store build number.
  String get buildNumber;

  /// `<version>+<build>`, as `X-Client-Version` sends it.
  String get versionWithBuild;

  /// `android` or `ios`, as `X-Platform` sends it.
  String get platform;
}

final class PackageInfoAppInfo implements AppInfo {
  const PackageInfoAppInfo._(this.version, this.buildNumber, this.platform);

  static Future<PackageInfoAppInfo> load() async {
    final info = await PackageInfo.fromPlatform();
    return PackageInfoAppInfo._(
      info.version,
      info.buildNumber,
      defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
    );
  }

  @override
  final String version;

  @override
  final String buildNumber;

  @override
  final String platform;

  @override
  String get versionWithBuild => '$version+$buildNumber';
}

@Riverpod(keepAlive: true)
Future<AppInfo> appInfo(Ref ref) => PackageInfoAppInfo.load();
