// `GET /v1/state` (B03 contracts/api.md): everything the server holds of
// the player at one `state_version`. `state_snapshot.dart` maps it to the
// economy's state.
import 'package:wassal/core/sync/domain/wire/iso_time.dart';
import 'package:wassal/core/sync/domain/wire/reader.dart';
import 'package:wassal/core/sync/domain/wire/server_wallet.dart';

/// One `ownership[]` row. `variant` is `""` for anything but an item.
final class StateOwnership {
  const StateOwnership({
    required this.kind,
    required this.skuId,
    required this.variant,
  });

  final String kind;
  final String skuId;
  final String variant;
}

/// One `trips[]` row.
final class StateTrip {
  const StateTrip({
    required this.tripId,
    required this.bestStars,
    required this.plays,
    this.bestTimeMs,
  });

  final String tripId;
  final int bestStars;
  final int? bestTimeMs;
  final int plays;
}

/// `open_trip`: the server's unfinished start.
final class StateOpenTrip {
  const StateOpenTrip({
    required this.startTxn,
    required this.tripId,
    required this.contentVersion,
    required this.revived,
    required this.trafficJamAds,
  });

  final String startTxn;
  final String tripId;
  final int contentVersion;
  final bool revived;
  final int trafficJamAds;
}

/// `story`: the chapters' seen scenes and the claimed requests
/// (specs/015-m10-apartment-story, contracts/economy-ops.md "The server's
/// state"). A `status` isn't kept: completion is derived (FR-051).
final class StateStory {
  const StateStory({this.chapters = const [], this.requestsClaimed = const []});

  static const empty = StateStory();

  final List<StateChapter> chapters;
  final List<String> requestsClaimed;
}

/// One `story.chapters[]` row.
final class StateChapter {
  const StateChapter({required this.chapterId, this.scenesSeen = const []});

  final String chapterId;
  final List<String> scenesSeen;
}

/// `grants`: what the server gave once (M07 research R8).
final class StateGrants {
  const StateGrants({required this.tutorial});

  /// The fuel lesson's gift. Absent reads as false.
  final bool tutorial;
}

/// `last_result`, in M05's `LastResult` JSON shape.
final class StateLastResult {
  const StateLastResult(this.json);

  /// `{start_txn, outcome, earnings_jenehat, doubled}`.
  final Map<String, Object?> json;
}

final class StateSnapshot {
  const StateSnapshot({
    required this.stateVersion,
    required this.serverTimeMs,
    required this.wallet,
    required this.inventory,
    required this.ownership,
    required this.trips,
    required this.raw,
    this.grants = const StateGrants(tutorial: false),
    this.displayName,
    this.driverLevel,
    this.openTrip,
    this.lastResult,
    this.story = StateStory.empty,
  });

  factory StateSnapshot.fromJson(Object? json) {
    final o = WireObject.of(json);
    final player = o.object('player');
    final inventory = o.object('inventory');
    final open = o.optionalObject('open_trip');
    final last = o.optionalObject('last_result');
    final grants = o.optionalObject('grants');
    final story = o.optionalObject('story');
    return StateSnapshot(
      stateVersion: o.integer('state_version'),
      serverTimeMs: o.time('server_time'),
      displayName: player.optionalText('display_name'),
      driverLevel: player.optionalInteger('driver_level'),
      wallet: ServerWallet.fromJson(o.raw['wallet']),
      inventory: {
        for (final key in inventory.raw.keys) key: inventory.integer(key),
      },
      ownership: [
        for (final row in o.objects('ownership'))
          StateOwnership(
            kind: row.string('kind'),
            skuId: row.string('sku_id'),
            variant: row.optionalString('variant') ?? '',
          ),
      ],
      trips: [
        for (final row in o.objects('trips'))
          StateTrip(
            tripId: row.string('trip_id'),
            bestStars: row.integer('best_stars'),
            bestTimeMs: row.optionalInteger('best_time_ms'),
            plays: row.integer('plays'),
          ),
      ],
      openTrip: open == null
          ? null
          : StateOpenTrip(
              startTxn: open.string('start_txn'),
              tripId: open.string('trip_id'),
              contentVersion: open.integer('content_version'),
              revived: open.boolean('revived'),
              trafficJamAds: open.integer('traffic_jam_ads'),
            ),
      lastResult: last == null
          ? null
          : StateLastResult({
              'start_txn': last.string('start_txn'),
              'outcome': last.string('outcome'),
              'earnings_jenehat': last.integer('earnings_jenehat'),
              'doubled': last.boolean('doubled'),
            }),
      grants: StateGrants(
        tutorial: grants != null && grants.has('tutorial')
            ? grants.boolean('tutorial')
            : false,
      ),
      story: story == null
          ? StateStory.empty
          : StateStory(
              chapters: [
                for (final row in story.objects('chapters'))
                  StateChapter(
                    chapterId: row.string('chapter_id'),
                    scenesSeen: row.has('scenes_seen')
                        ? row.strings('scenes_seen')
                        : const [],
                  ),
              ],
              requestsClaimed: story.has('requests_claimed')
                  ? story.strings('requests_claimed')
                  : const [],
            ),
      raw: o.raw,
    );
  }

  final int stateVersion;
  final int serverTimeMs;
  final String? displayName;
  final int? driverLevel;
  final ServerWallet wallet;

  /// By booster id, zero counts included.
  final Map<String, int> inventory;
  final List<StateOwnership> ownership;
  final List<StateTrip> trips;
  final StateOpenTrip? openTrip;
  final StateLastResult? lastResult;
  final StateGrants grants;
  final StateStory story;

  /// The answer as it arrived: `stats` is read by a later feature (M13).
  final Map<String, Object?> raw;
}
