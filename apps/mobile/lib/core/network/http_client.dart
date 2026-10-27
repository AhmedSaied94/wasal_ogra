// The app's HTTP client (specs/006-m04-content-loader/contracts/updates.md
// "Requests"). No token here: the content endpoints stay public (B04
// FR-033, B02 FR-035). Every other /v1 call carries the player's token,
// which `AuthorizedApi` adds per request (specs/011-m06-identity-sync,
// research R3).
import 'package:dio/dio.dart';
import 'package:wassal/bootstrap/flavor.dart';
import 'package:wassal/core/network/api_environment.dart';
import 'package:wassal/core/platform/app_info.dart';

/// The manifest body's cap (64 KiB), counted while streaming.
const manifestMaxBytes = 65536;

/// The largest pack the app downloads (16 MiB).
const downloadMaxBytes = 16777216;

const connectTimeout = Duration(seconds: 10);
const manifestReceiveTimeout = Duration(seconds: 10);

/// The longest a download may wait between two chunks.
const downloadChunkTimeout = Duration(seconds: 30);

/// The longest one download may take.
const downloadTotalTimeout = Duration(seconds: 120);

/// A client that never follows redirects and accepts every status, so the
/// caller decides: only `200` counts as success.
Dio createHttpClient(Flavor flavor, AppInfo info) => Dio(
  BaseOptions(
    baseUrl: apiBaseUrl(flavor),
    connectTimeout: connectTimeout,
    followRedirects: false,
    maxRedirects: 0,
    validateStatus: (_) => true,
    headers: {
      'X-Client-Version': info.versionWithBuild,
      'X-Platform': info.platform,
    },
  ),
);
