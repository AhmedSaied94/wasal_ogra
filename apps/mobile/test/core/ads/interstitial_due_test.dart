import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/ads/domain/interstitial_due.dart';

// When an interstitial shows between trips (specs/018-m11-ads, research R10,
// glossary §3.4, T021).

bool _due({
  int trips = 10,
  int lastInterstitialAt = 0,
  int lastRewardedAt = 0,
  bool tutorialDone = true,
  bool removeAds = false,
  bool noInterstitials = false,
  bool online = true,
  bool loaded = true,
  int grace = 10,
  int everyN = 3,
}) => interstitialDue(
  trips: trips,
  lastInterstitialAt: lastInterstitialAt,
  lastRewardedAt: lastRewardedAt,
  tutorialDone: tutorialDone,
  removeAds: removeAds,
  noInterstitials: noInterstitials,
  online: online,
  loaded: loaded,
  graceTrips: grace,
  everyNTrips: everyN,
);

void main() {
  test('the grace: trip 9 no, trip 10 yes', () {
    expect(_due(trips: 9), isFalse);
    expect(_due(trips: 10), isTrue);
  });

  test('the cadence: 2 trips since the last no, 3 yes', () {
    expect(_due(trips: 14, lastInterstitialAt: 12), isFalse);
    expect(_due(trips: 15, lastInterstitialAt: 12), isTrue);
  });

  test('never right after a rewarded ad paid', () {
    expect(_due(trips: 12, lastRewardedAt: 12), isFalse);
    expect(_due(trips: 12, lastRewardedAt: 11), isTrue);
  });

  test('each condition alone stops it', () {
    expect(_due(tutorialDone: false), isFalse);
    expect(_due(removeAds: true), isFalse);
    expect(_due(noInterstitials: true), isFalse);
    expect(_due(online: false), isFalse);
    expect(_due(loaded: false), isFalse);
  });

  test('grace and cadence come from the tunables, edges included', () {
    expect(_due(trips: 1, grace: 0, everyN: 1), isTrue);
    expect(_due(trips: 0, grace: 0, everyN: 0, lastRewardedAt: -1), isTrue);
    expect(_due(trips: 1, grace: 1, everyN: 1, lastInterstitialAt: 1), isFalse);
    expect(_due(trips: 2, grace: 1, everyN: 1, lastInterstitialAt: 1), isTrue);
    expect(_due(trips: 5, grace: 6), isFalse);
  });
}
