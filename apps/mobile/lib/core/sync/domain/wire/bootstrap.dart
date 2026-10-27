// `GET /v1/bootstrap` (B03 contracts/api.md). Its blocks are cached in
// `server_info` as they arrived, and read back with the same readers
// (research R15).
import 'package:wassal/core/sync/domain/wire/iso_time.dart';
import 'package:wassal/core/sync/domain/wire/reader.dart';
import 'package:wassal/core/sync/domain/wire/server_wallet.dart';

/// The app-version block: `force_update` is the server's verdict on this
/// build (research R18).
final class ClientBlock {
  const ClientBlock({
    required this.minVersion,
    required this.latestVersion,
    required this.forceUpdate,
  });

  factory ClientBlock.fromJson(Object? json, [String path = 'client']) {
    final o = WireObject.of(json, path);
    return ClientBlock(
      minVersion: o.string('min_version'),
      latestVersion: o.string('latest_version'),
      forceUpdate: o.boolean('force_update'),
    );
  }

  final String minVersion;
  final String latestVersion;
  final bool forceUpdate;
}

/// A read-only cache of the server's entitlements (constitution IV). Neutral
/// until B06: the subscription's shape is B06's, so only an `until` time is
/// read from it.
final class Entitlements {
  const Entitlements({
    required this.removeAds,
    required this.seasonPasses,
    required this.noInterstitials,
    required this.fuelMaxBonus,
    this.subscriptionUntilMs,
  });

  factory Entitlements.fromJson(Object? json, [String path = 'entitlements']) {
    final o = WireObject.of(json, path);
    final flags = o.optionalObject('flags');
    final subscription = o.optionalObject('subscription');
    return Entitlements(
      removeAds: o.boolean('remove_ads'),
      subscriptionUntilMs: subscription?.optionalTime('until'),
      seasonPasses: List.unmodifiable(o.list('season_passes')),
      noInterstitials: flags != null && flags.has('no_interstitials')
          ? flags.boolean('no_interstitials')
          : false,
      fuelMaxBonus: flags?.optionalInteger('fuel_max_bonus') ?? 0,
    );
  }

  static const neutral = Entitlements(
    removeAds: false,
    seasonPasses: [],
    noInterstitials: false,
    fuelMaxBonus: 0,
  );

  final bool removeAds;
  final int? subscriptionUntilMs;

  /// As the server sent them, for M12.
  final List<Object?> seasonPasses;
  final bool noInterstitials;
  final int fuelMaxBonus;
}

/// The daily block: neutral until B08 and M13.
final class DailyBlock {
  const DailyBlock({
    required this.gameDate,
    required this.challengeAvailable,
    required this.rewardClaimable,
  });

  factory DailyBlock.fromJson(Object? json, [String path = 'daily']) {
    final o = WireObject.of(json, path);
    return DailyBlock(
      gameDate: o.string('game_date'),
      challengeAvailable: o.boolean('challenge_available'),
      rewardClaimable: o.boolean('reward_claimable'),
    );
  }

  /// `YYYY-MM-DD`, Cairo's game day.
  final String gameDate;
  final bool challengeAvailable;
  final bool rewardClaimable;
}

/// The bootstrap's `player` block.
final class BootstrapPlayer {
  const BootstrapPlayer({
    required this.playerId,
    required this.providers,
    this.displayName,
    this.driverLevel,
  });

  factory BootstrapPlayer.fromJson(Object? json) {
    final o = WireObject.of(json, 'player');
    return BootstrapPlayer(
      playerId: o.string('player_id'),
      providers: o.strings('providers'),
      displayName: o.optionalString('display_name'),
      driverLevel: o.optionalInteger('driver_level'),
    );
  }

  final String playerId;
  final List<String> providers;
  final String? displayName;
  final int? driverLevel;
}

/// The whole answer.
final class BootstrapSnapshot {
  const BootstrapSnapshot({
    required this.serverTimeMs,
    required this.player,
    required this.wallet,
    required this.entitlements,
    required this.stateVersion,
    required this.client,
    required this.daily,
    required this.comebackClaimable,
    required this.raw,
    this.contentVersion,
  });

  factory BootstrapSnapshot.fromJson(Object? json) {
    final o = WireObject.of(json);
    return BootstrapSnapshot(
      serverTimeMs: o.time('server_time'),
      player: BootstrapPlayer.fromJson(o.raw['player']),
      wallet: ServerWallet.fromJson(o.raw['wallet']),
      entitlements: Entitlements.fromJson(o.raw['entitlements']),
      stateVersion: o.integer('state_version'),
      // Null while no pack is published.
      contentVersion: o.object('content').optionalInteger('version'),
      client: ClientBlock.fromJson(o.raw['client']),
      daily: DailyBlock.fromJson(o.raw['daily']),
      comebackClaimable: o.object('comeback').boolean('claimable'),
      raw: o.raw,
    );
  }

  final int serverTimeMs;
  final BootstrapPlayer player;

  /// Never applied: the state fetch or the next batch carries what it would
  /// (research R15).
  final ServerWallet wallet;
  final Entitlements entitlements;
  final int stateVersion;
  final int? contentVersion;
  final ClientBlock client;
  final DailyBlock daily;
  final bool comebackClaimable;

  /// The answer as it arrived, so the cache keeps each block whole.
  final Map<String, Object?> raw;
}
