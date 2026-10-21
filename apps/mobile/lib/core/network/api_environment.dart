// The API address of each flavor, and which URLs the app may call
// (specs/006-m04-content-loader/research.md R11, R12).
import 'package:wassal/bootstrap/flavor.dart';

/// The B01 dev stack on the developer's machine, reached from an emulator
/// or a phone through `adb reverse tcp:8000 tcp:8000`.
const devApiBase = 'http://localhost:8000';

// The hosts come from docs/runbooks/provision-host.md. The delivery plan's
// domain-switch item edits them here too: a shipped build keeps its host
// until the next app release.
const stagingApiBase = 'https://staging-api.141-147-129-92.sslip.io';
const prodApiBase = 'https://api.193-122-74-125.sslip.io';

/// The hosts the dev flavor may call over plain HTTP: the developer's own
/// machine (constitution 1.2.0, Security & privacy).
const devCleartextHosts = {'localhost', '127.0.0.1', '10.0.2.2'};

/// The API base URL for [flavor], without a trailing slash. A dev build may
/// point elsewhere with `--dart-define=WASSAL_DEV_API_BASE=…`.
String apiBaseUrl(
  Flavor flavor, {
  String devOverride = const String.fromEnvironment('WASSAL_DEV_API_BASE'),
}) => switch (flavor) {
  Flavor.dev => devOverride.isEmpty ? devApiBase : devOverride,
  Flavor.staging => stagingApiBase,
  Flavor.prod => prodApiBase,
};

/// Whether the app may request [uri]: `https` with a host, or, in dev only,
/// `http` to one of [devCleartextHosts]. Checked before every request.
bool isAllowedUrl(Flavor flavor, Uri uri) {
  if (!uri.hasAuthority || uri.host.isEmpty) return false;
  return switch (uri.scheme) {
    'https' => true,
    'http' => flavor == Flavor.dev && devCleartextHosts.contains(uri.host),
    _ => false,
  };
}
