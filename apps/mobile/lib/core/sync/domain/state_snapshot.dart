// The server's full state as the economy's (specs/011-m06-identity-sync,
// contracts/sync.md "Taking the full state", research R12). Pure.
import 'package:content_models/content_models.dart';
import 'package:wassal/core/content/domain/content_source.dart';
import 'package:wassal/core/economy/domain/economy_state.dart';
import 'package:wassal/core/economy/domain/txn_id.dart';
import 'package:wassal/core/economy/domain/wire.dart';
import 'package:wassal/core/sync/domain/wire/state.dart';

/// [snapshot] as an [EconomyState]:
/// - the wallet's balances and tank;
/// - the four in-trip boosters (a zero count is no entry);
/// - ownership with `""` variants as null, taken at `server_time` by no
///   operation of this phone's; kinds the economy can't own are skipped;
/// - trips as progress, with no first completion time;
/// - the open trip only when [hasTripRecord] says this phone has its
///   record and [content] has the trip, for its earnings bound;
/// - the last result;
/// - since M07, the player's name and the tutorial grant
///   (specs/012-m07-onboarding research R8);
/// - since M10, the story's seen scenes by chapter and the claimed requests
///   (contracts/economy-ops.md "The server's state").
///
/// `stats` isn't mapped yet (M13). Ids the pack lacks are kept (FR-026).
EconomyState stateFromSnapshot(
  StateSnapshot snapshot, {
  required bool Function(TxnId start) hasTripRecord,
  required ContentSource content,
}) => EconomyState(
  jenehat: snapshot.wallet.jenehat,
  bonat: snapshot.wallet.bonat,
  fuel: snapshot.wallet.fuelState,
  inventory: {
    for (final MapEntry(key: wire, value: count) in snapshot.inventory.entries)
      if (fromWire(boosterWire, wire) case final booster?
          when inTripBoosters.contains(booster) && count > 0)
        booster: count,
  },
  ownership: {
    for (final row in snapshot.ownership)
      if (_owned(row, snapshot.serverTimeMs) case (final key, final owned))
        key: owned,
  },
  progress: {
    for (final trip in snapshot.trips)
      trip.tripId: TripProgress(
        bestStars: trip.bestStars,
        bestTimeMs: trip.bestTimeMs,
        plays: trip.plays,
      ),
  },
  unfinished: _unfinished(snapshot, hasTripRecord, content),
  lastResult: switch (snapshot.lastResult) {
    final last? => LastResult.fromJson(last.json),
    null => null,
  },
  displayName: snapshot.displayName,
  tutorialGranted: snapshot.grants.tutorial,
  scenesSeen: {
    for (final chapter in snapshot.story.chapters)
      if (chapter.scenesSeen.isNotEmpty)
        chapter.chapterId: {...chapter.scenesSeen},
  },
  requestsClaimed: {...snapshot.story.requestsClaimed},
);

(OwnedKey, Owned)? _owned(StateOwnership row, int serverTimeMs) {
  final kind = fromWire(skuKindWire, row.kind);
  if (kind == null || !ownableKinds.contains(kind)) return null;
  final variant = row.variant.isEmpty ? null : row.variant;
  // An item needs its variant, and nothing else has one.
  if ((kind == SkuKind.item) != (variant != null)) return null;
  return (
    (kind, row.skuId),
    Owned(kind: kind, variantId: variant, acquiredAtMs: serverTimeMs),
  );
}

UnfinishedTrip? _unfinished(
  StateSnapshot snapshot,
  bool Function(TxnId start) hasTripRecord,
  ContentSource content,
) {
  final open = snapshot.openTrip;
  if (open == null) return null;
  final TxnId start;
  try {
    start = TxnId.parse(open.startTxn);
  } on FormatException {
    return null;
  }
  // A start played on another phone is never offered for resuming here;
  // this phone's next start closes it on the server (FR-026).
  if (!hasTripRecord(start)) return null;
  final trip = content.trip(open.tripId);
  if (trip == null) return null;
  return UnfinishedTrip(
    startTxn: start,
    tripId: open.tripId,
    contentVersion: open.contentVersion,
    maxEarningsJenehat: trip.maxEarningsJenehat,
    startedAtMs: snapshot.serverTimeMs,
    revived: open.revived,
    trafficJamAds: open.trafficJamAds,
  );
}
