// `AdsGateway` over `google_mobile_ads` (specs/018-m11-ads, research R1, R5,
// R6, R16): the only file that imports the SDK (`test/repo/
// no_ads_in_trip_test.dart`). AppLovin's and Unity's adapters need no Dart
// call: their dependencies register them with the SDK. It has no unit test,
// because the plugin needs a device; quickstart §3 covers it.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:wassal/core/ads/ads_gateway.dart';
import 'package:wassal/core/ads/domain/ad_timing.dart';

/// One loaded ad and when it loaded.
typedef _Held = ({Ad ad, int loadedAtMs});

final class GmaAdsGateway implements AdsGateway, AdsDebugControls {
  GmaAdsGateway({
    required this._units,
    required this._debugAllowed,
    int Function()? nowMs,
  }) : _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch) {
    for (final unit in AdUnit.values) {
      _readiness[unit] = ValueNotifier(Readiness.notLoaded);
    }
  }

  /// The flavor's unit id per unit (`ad_ids.dart`).
  final Map<AdUnit, String> _units;

  /// Dev only: the debug geography and the consent reset.
  final bool _debugAllowed;
  final int Function() _nowMs;
  final _readiness = <AdUnit, ValueNotifier<Readiness>>{};
  final _held = <AdUnit, _Held>{};

  /// The longest the consent form's callback is waited for.
  static const _consentWait = Duration(minutes: 2);

  /// The longest a load's callbacks are waited for.
  static const _loadWait = Duration(seconds: 60);

  final _failures = <AdUnit, int>{};
  final _retryAtMs = <AdUnit, int>{};

  @override
  ConsentGeography geography = ConsentGeography.none;

  @override
  bool formShown = false;

  @override
  Future<bool> start(RequestConfig config) async {
    await _updateConsent();
    var shown = false;
    final dismissed = Completer<void>();
    await ConsentForm.loadAndShowConsentFormIfRequired((error) {
      shown = error == null;
      if (!dismissed.isCompleted) dismissed.complete();
    });
    // A lost callback (the activity recreated, say) would hold every later
    // checkpoint: past the wait, this launch has no ads.
    try {
      await dismissed.future.timeout(_consentWait);
    } on TimeoutException {
      return false;
    }
    formShown = shown;
    final canRequest = await ConsentInformation.instance.canRequestAds();
    if (!canRequest) return false;
    // Before the SDK starts, so the first request carries it (research R5).
    await MobileAds.instance.updateRequestConfiguration(_configOf(config));
    await MobileAds.instance.initialize();
    return true;
  }

  Future<void> _updateConsent() {
    final done = Completer<void>();
    final debug = _debugAllowed && geography != ConsentGeography.none
        ? ConsentDebugSettings(
            debugGeography: switch (geography) {
              ConsentGeography.eea => DebugGeography.debugGeographyEea,
              ConsentGeography.notEea => DebugGeography.debugGeographyOther,
              ConsentGeography.none => DebugGeography.debugGeographyDisabled,
            },
          )
        : null;
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(consentDebugSettings: debug),
      done.complete,
      // Offline or failed: UMP keeps its cached status, which
      // `canRequestAds` reads next.
      (_) => done.complete(),
    );
    return done.future;
  }

  /// [config] in the SDK's types, field by field, with no defaults of its
  /// own (analysis G1). The two tags are the deprecated fields because the
  /// newer `ageRestrictedTreatment` has no "not under age" value to send
  /// (research R5 sends an explicit no).
  static RequestConfiguration _configOf(RequestConfig config) =>
      RequestConfiguration(
        maxAdContentRating: switch (config.rating) {
          AdContentRating.g => MaxAdContentRating.g,
          AdContentRating.pg => MaxAdContentRating.pg,
          AdContentRating.t => MaxAdContentRating.t,
          AdContentRating.ma => MaxAdContentRating.ma,
        },
        // ignore: deprecated_member_use
        tagForChildDirectedTreatment: switch (config.childDirected) {
          // ignore: deprecated_member_use
          true => TagForChildDirectedTreatment.yes,
          // ignore: deprecated_member_use
          false => TagForChildDirectedTreatment.no,
        },
        // ignore: deprecated_member_use
        tagForUnderAgeOfConsent: switch (config.underAgeOfConsent) {
          // ignore: deprecated_member_use
          true => TagForUnderAgeOfConsent.yes,
          // ignore: deprecated_member_use
          false => TagForUnderAgeOfConsent.no,
        },
        testDeviceIds: config.testDeviceIds,
      );

  @override
  Future<void> resetConsent() async {
    if (!_debugAllowed) return;
    await ConsentInformation.instance.reset();
  }

  @override
  ValueListenable<Readiness> readiness(AdUnit unit) => _readiness[unit]!;

  @override
  Future<void> load(AdUnit unit) async {
    final readiness = _readiness[unit]!;
    final now = _nowMs();
    final held = _held[unit];
    if (held != null) {
      if (now - held.loadedAtMs < adExpiryMs) return;
      // Expired: dropped and loaded again (research R16).
      unawaited(held.ad.dispose());
      _held.remove(unit);
    }
    if (readiness.value == Readiness.loading) return;
    if (now < (_retryAtMs[unit] ?? 0)) return;
    readiness.value = Readiness.loading;
    final loaded = Completer<Ad?>();
    void onFailed(LoadAdError error) {
      if (!loaded.isCompleted) loaded.complete(null);
    }

    void onLoaded(Ad ad) {
      if (loaded.isCompleted) {
        // Past the wait: nobody holds it.
        unawaited(ad.dispose());
      } else {
        loaded.complete(ad);
      }
    }

    final id = _units[unit]!;
    try {
      await _request(unit, id, onLoaded, onFailed);
    } on Exception {
      if (!loaded.isCompleted) loaded.complete(null);
    }
    final ad = await loaded.future.timeout(_loadWait, onTimeout: () => null);
    if (ad == null) {
      final failures = (_failures[unit] ?? 0) + 1;
      _failures[unit] = failures;
      _retryAtMs[unit] = _nowMs() + backoffAfter(failures);
      readiness.value = Readiness.failed;
      return;
    }
    _failures.remove(unit);
    _retryAtMs.remove(unit);
    _held[unit] = (ad: ad, loadedAtMs: _nowMs());
    readiness.value = Readiness.ready;
  }

  Future<void> _request(
    AdUnit unit,
    String id,
    void Function(Ad ad) onLoaded,
    void Function(LoadAdError error) onFailed,
  ) async {
    if (unit == AdUnit.interstitial) {
      await InterstitialAd.load(
        adUnitId: id,
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: onLoaded,
          onAdFailedToLoad: onFailed,
        ),
      );
    } else {
      await RewardedAd.load(
        adUnitId: id,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: onLoaded,
          onAdFailedToLoad: onFailed,
        ),
      );
    }
  }

  @override
  Future<ShowOutcome> show(
    AdUnit unit, {
    PiggyVerification? verification,
  }) async {
    final held = _held.remove(unit);
    _readiness[unit]!.value = Readiness.notLoaded;
    if (held == null || _nowMs() - held.loadedAtMs >= adExpiryMs) {
      unawaited(held?.ad.dispose());
      return const ShowFailed();
    }
    final done = Completer<ShowOutcome>();
    var earned = false;
    void finish(Ad ad, ShowOutcome outcome) {
      unawaited(ad.dispose());
      if (!done.isCompleted) done.complete(outcome);
    }

    switch (held.ad) {
      case final RewardedAd ad:
        if (verification != null) {
          await ad.setServerSideOptions(
            ServerSideVerificationOptions(
              userId: verification.userId,
              customData: verification.customData,
            ),
          );
        }
        ad.fullScreenContentCallback = FullScreenContentCallback(
          // The reward fires before the dismissal (contracts/ads-gateway.md).
          onAdDismissedFullScreenContent: (ad) =>
              finish(ad, earned ? const Rewarded() : const Closed()),
          onAdFailedToShowFullScreenContent: (ad, _) =>
              finish(ad, const ShowFailed()),
        );
        await ad.show(onUserEarnedReward: (_, _) => earned = true);
      case final InterstitialAd ad:
        ad.fullScreenContentCallback = FullScreenContentCallback(
          onAdDismissedFullScreenContent: (ad) => finish(ad, const Closed()),
          onAdFailedToShowFullScreenContent: (ad, _) =>
              finish(ad, const ShowFailed()),
        );
        await ad.show();
      default:
        unawaited(held.ad.dispose());
        return const ShowFailed();
    }
    return done.future;
  }
}
