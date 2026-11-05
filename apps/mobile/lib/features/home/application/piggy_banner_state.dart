// What Home's morning piggy draws (specs/018-m11-ads, contracts/seams.md
// "`PiggyBanner`"): the ads layer's offer, or the wheel while the piggy
// asks the server for its reward.
import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wassal/core/ads/ads_providers.dart';
import 'package:wassal/core/ads/ads_service.dart';
import 'package:wassal/core/economy/economy.dart' show AdPlacement;

part 'piggy_banner_state.g.dart';

enum PiggyBannerState { hidden, ready, notReady, offline, asking }

/// The banner's state from the ads layer's [offer] and the piggy's
/// [asking].
PiggyBannerState piggyBannerStateOf(AdOffer offer, {required bool asking}) {
  if (asking) return PiggyBannerState.asking;
  return switch (offer) {
    Offered() => PiggyBannerState.ready,
    NotReady() => PiggyBannerState.notReady,
    NeedsNetwork() => PiggyBannerState.offline,
    LimitReached() || Hidden() => PiggyBannerState.hidden,
  };
}

/// Not ready on Home: the piggy's ad loads now (research R16, "Home's
/// appearance"), and the offer follows when it has.
@riverpod
PiggyBannerState piggyBanner(Ref ref) {
  final piggy = ref.watch(piggyServiceProvider);
  void changed() => ref.invalidateSelf();
  piggy.asking.addListener(changed);
  ref.onDispose(() => piggy.asking.removeListener(changed));
  final state = piggyBannerStateOf(
    ref.watch(adOfferNowProvider(AdPlacement.morningPiggy)),
    asking: piggy.asking.value,
  );
  if (state == PiggyBannerState.notReady) {
    final ads = ref.read(adsServiceProvider);
    unawaited(
      ads
          .ensureReady()
          .then((_) => ads.preload(AdPlacement.morningPiggy))
          // The banner stays «not ready»; the next build tries again.
          .catchError((Object _) {}),
    );
  }
  return state;
}
