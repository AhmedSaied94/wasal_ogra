// Every ad request's configuration (specs/018-m11-ads, research R5, FR-025):
// the stores list the game as 13+, not designed for children. Pure, so the
// rule is tested without the plugin (analysis G1); `GmaAdsGateway` only maps
// it onto the SDK's types.

/// The highest ad content rating allowed.
enum AdContentRating { g, pg, t, ma }

final class RequestConfig {
  const RequestConfig({
    required this.rating,
    required this.childDirected,
    required this.underAgeOfConsent,
    required this.testDeviceIds,
  });

  final AdContentRating rating;
  final bool childDirected;
  final bool underAgeOfConsent;

  /// Always empty in code: staging uses the AdMob console's test devices.
  final List<String> testDeviceIds;

  @override
  bool operator ==(Object other) =>
      other is RequestConfig &&
      other.rating == rating &&
      other.childDirected == childDirected &&
      other.underAgeOfConsent == underAgeOfConsent &&
      _sameIds(other.testDeviceIds, testDeviceIds);

  @override
  int get hashCode => Object.hash(
    rating,
    childDirected,
    underAgeOfConsent,
    testDeviceIds.length,
  );

  @override
  String toString() =>
      'RequestConfig($rating, childDirected: $childDirected, '
      'underAgeOfConsent: $underAgeOfConsent, testDevices: $testDeviceIds)';
}

bool _sameIds(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Rating T, not child-directed, not under the age of consent, no test
/// devices (research R5).
RequestConfig adRequestConfig() => const RequestConfig(
  rating: AdContentRating.t,
  childDirected: false,
  underAgeOfConsent: false,
  testDeviceIds: [],
);
