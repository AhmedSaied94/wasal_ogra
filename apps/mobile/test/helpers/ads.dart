// What the ads tests share (specs/018-m11-ads): a scripted `AdsWorld`, and
// an `AdsServiceImpl` over the fake gateway and a real economy.
import 'package:flutter/foundation.dart';
import 'package:wassal/core/ads/ads_service.dart';
import 'package:wassal/core/config/config_source.dart';
import 'package:wassal/core/config/tunable.dart';
import 'package:wassal/core/economy/economy.dart';
import 'package:wassal/core/economy/domain/game_day.dart';
import 'package:wassal/core/sync/domain/wire/bootstrap.dart';

import 'economy.dart';
import 'fake_ads_gateway.dart';
import 'memory_settings_store.dart';

/// The ad tunables at their bundled defaults, the rest from [inner].
final class AdTunables implements ConfigSource {
  AdTunables(this.inner);

  final ConfigSource inner;
  int graceTrips = 10;
  int everyNTrips = 3;
  int refillCap = 3;
  int piggyCap = 1;

  @override
  T read<T extends Object>(Tunable<T> key) {
    if (identical(key, Tunable.adsInterstitialGraceTrips)) {
      return graceTrips as T;
    }
    if (identical(key, Tunable.adsInterstitialEveryNTrips)) {
      return everyNTrips as T;
    }
    if (identical(key, Tunable.adsFuelRefillDailyCap)) return refillCap as T;
    if (identical(key, Tunable.adsMorningPiggyDailyCap)) return piggyCap as T;
    return inner.read(key);
  }
}

/// A scripted [AdsWorld] over a real economy's view.
final class FakeAdsWorld implements AdsWorld {
  FakeAdsWorld(this.economy, {this.tutorialTrips = const []})
    : tunables = AdTunables(economy.tunables);

  final TestEconomy economy;
  final List<String> tutorialTrips;

  @override
  bool online = true;

  @override
  Entitlements entitlements = Entitlements.neutral;

  @override
  bool tutorialDone = true;

  @override
  int tutorialFinished = 5;

  @override
  AdsBlock? adsBlock;

  /// The cached bootstrap's day; today's unless a test sets it.
  String? gameDay;

  @override
  final AdTunables tunables;

  @override
  int? tutorialIndexOf(String tripId) {
    final index = tutorialTrips.indexOf(tripId);
    return index < 0 ? null : index;
  }

  @override
  EconomyView get view => economy.service.view;

  @override
  String? get bootstrapGameDay => gameDay ?? gameDayOf(nowMs());

  @override
  int nowMs() => economy.clock.nowMs();
}

/// The service and everything it was built over.
final class AdsRig {
  AdsRig._(this.economy, this.gateway, this.settings, this.world, this.probe)
    : service = AdsServiceImpl(
        gateway: gateway,
        economy: economy.service,
        settings: settings,
        world: world,
        probe: probe,
      );

  static Future<AdsRig> open({
    TestEconomy? economy,
    FakeAdsGateway? gateway,
    List<String> tutorialTrips = const [],
  }) async {
    final e = economy ?? await testEconomy();
    final probe = ValueNotifier(false);
    final g = gateway ?? FakeAdsGateway();
    g.failOnCallWhileRunning(probe);
    return AdsRig._(
      e,
      g,
      MemorySettingsStore(),
      FakeAdsWorld(e, tutorialTrips: tutorialTrips),
      probe,
    );
  }

  final TestEconomy economy;
  final FakeAdsGateway gateway;
  final MemorySettingsStore settings;
  final FakeAdsWorld world;
  final ValueNotifier<bool> probe;
  final AdsServiceImpl service;
}
