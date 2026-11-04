// The ads' providers (specs/018-m11-ads, contracts/ads-gateway.md): the
// gateway, the service and what the buttons watch. Tests override
// [adsGatewayProvider] with `test/helpers/fake_ads_gateway.dart`.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wassal/bootstrap/flavor.dart';
import 'package:wassal/core/account/account_providers.dart';
import 'package:wassal/bootstrap/startup.dart';
import 'package:wassal/core/ads/ad_ids.dart';
import 'package:wassal/core/ads/ads_gateway.dart';
import 'package:wassal/core/ads/ads_service.dart';
import 'package:wassal/core/ads/gma_ads_gateway.dart';
import 'package:wassal/core/ads/piggy_api.dart';
import 'package:wassal/core/ads/piggy_service.dart';
import 'package:wassal/core/config/config_providers.dart';
import 'package:wassal/core/config/config_source.dart';
import 'package:wassal/core/economy/economy.dart';
import 'package:wassal/core/economy/economy_providers.dart';
import 'package:wassal/core/sync/domain/wire/bootstrap.dart';
import 'package:wassal/core/sync/server_status.dart';
import 'package:wassal/core/sync/sync_providers.dart';
import 'package:wassal/features/onboarding/domain/first_session.dart';
import 'package:wassal/features/onboarding/onboarding_providers.dart';
import 'package:wassal/features/trip/trip_providers.dart';

part 'ads_providers.g.dart';

/// The SDK behind its interface, with this flavor's and platform's units.
@Riverpod(keepAlive: true)
AdsGateway adsGateway(Ref ref) {
  final flavor = ref.watch(flavorProvider);
  final ids = adIds[flavor]!;
  return GmaAdsGateway(
    units: defaultTargetPlatform == TargetPlatform.iOS
        ? ids.iosUnits
        : ids.androidUnits,
    debugAllowed: flavor == Flavor.dev,
  );
}

/// Gets a placement's ad ready where nothing else has (the refill offer on
/// the way to an empty tank's card, review H1).
typedef AdWarmUp = void Function(AdPlacement placement);

/// Nothing: tests and samples never reach the SDK by opening a card.
void noAdWarmUp(AdPlacement _) {}

/// The app's: the SDK's start, then the unit, never while a trip runs (the
/// service checks). A failure leaves the offer «not ready».
AdWarmUp liveAdWarmUp(Ref ref) => (placement) {
  final ads = ref.read(adsServiceProvider);
  unawaited(
    ads
        .ensureReady()
        .then((_) => ads.preload(placement))
        .catchError((Object _) {}),
  );
};

/// [noAdWarmUp] by default; the app's scope takes [liveAdWarmUp]
/// (`lib/bootstrap/ads_overrides.dart`).
@Riverpod(keepAlive: true)
AdWarmUp adWarmUp(Ref ref) => noAdWarmUp;

/// True exactly while a trip's engine runs (research R7).
@Riverpod(keepAlive: true)
TripRunningProbe tripRunningProbe(Ref ref) => ref.watch(tripRunningProvider);

/// The rest of the app, as the service reads it each time it decides.
final class _RefAdsWorld implements AdsWorld {
  _RefAdsWorld(this._ref);

  final Ref _ref;

  FirstSession get _session => _ref.read(firstSessionProvider);

  @override
  bool get online => _ref.read(isOnlineProvider);

  @override
  Entitlements get entitlements => _ref.read(entitlementsProvider);

  @override
  bool get tutorialDone => _session.tutorialDone;

  @override
  int get tutorialFinished {
    final facts = _session.facts;
    return facts.tutorialTrips
        .where((trip) => isFinished(facts.progress[trip]))
        .length;
  }

  @override
  int? tutorialIndexOf(String tripId) {
    final index = _session.facts.tutorialTrips.indexOf(tripId);
    return index < 0 ? null : index;
  }

  @override
  EconomyView get view => _ref.read(economyViewProvider);

  @override
  AdsBlock? get adsBlock => _ref.read(adsBlockProvider);

  @override
  String? get bootstrapGameDay => _ref.read(dailyBlockProvider)?.gameDate;

  @override
  int nowMs() => _ref.read(trustedClockProvider).requireValue.nowMs();

  @override
  ConfigSource get tunables => _ref.read(configSourceProvider);
}

@Riverpod(keepAlive: true)
AdsService adsService(Ref ref) {
  final service = AdsServiceImpl(
    gateway: ref.watch(adsGatewayProvider),
    economy: ref.watch(economyProvider).requireValue,
    settings: ref.watch(settingsStoreProvider).requireValue,
    world: _RefAdsWorld(ref),
    probe: ref.watch(tripRunningProbeProvider),
  );
  ref.onDispose(service.dispose);
  return service;
}

/// What [placement]'s button shows now, for the result's [tripId] when it
/// has one. Rebuilt on every change the service, the economy, the network,
/// the entitlements or the cached bootstrap make.
@riverpod
AdOffer adOfferNow(Ref ref, AdPlacement placement, {String? tripId}) {
  final service = ref.watch(adsServiceProvider);
  ref
    ..watch(economyViewProvider)
    ..watch(isOnlineProvider)
    ..watch(entitlementsProvider)
    ..watch(adsBlockProvider);
  final changes = service.offersChanged.listen((_) => ref.invalidateSelf());
  ref.onDispose(() => unawaited(changes.cancel()));
  return service.offer(placement, tripId: tripId);
}

/// The morning piggy: its ad, the asks for the server's grant and the
/// outcome (research R12).
@Riverpod(keepAlive: true)
PiggyService piggyService(Ref ref) {
  final service = PiggyService(
    ads: ref.watch(adsServiceProvider),
    api: PiggyApi(ref.watch(authorizedApiProvider)),
    economy: ref.watch(economyProvider).requireValue,
    playerId: () => ref.read(profileProvider)?.playerId,
    requestSync: (trigger) =>
        ref.read(syncEngineProvider).value?.request(trigger),
  );
  ref.onDispose(service.dispose);
  return service;
}
