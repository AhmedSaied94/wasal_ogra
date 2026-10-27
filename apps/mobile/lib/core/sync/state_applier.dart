// Takes the server's full state into the phone (specs/011-m06-identity-
// sync, contracts/sync.md "Taking the full state", research R7, R12, R15):
// the economy's base, the profile, and trusted time.
import 'dart:async';

import 'package:wassal/core/content/domain/content_source.dart';
import 'package:wassal/core/economy/domain/txn_id.dart';
import 'package:wassal/core/economy/economy_sync.dart';
import 'package:wassal/core/sync/domain/state_snapshot.dart';
import 'package:wassal/core/sync/domain/wire/state.dart';
import 'package:wassal/core/sync/sync_engine.dart';
import 'package:wassal/features/trip/data/trip_records.dart';

/// Writes what the server last said of the player to the account.
typedef ProfileWriter = Future<void> Function({
  String? displayName,
  int? driverLevel,
});

final class ServerStateApplier implements StateApplier {
  ServerStateApplier({
    required this._economy,
    required this._trips,
    required this._content,
    required this._writeProfile,
  });

  final EconomySync _economy;
  final TripRecords _trips;

  /// The active pack, for an open trip's earnings bound. A restore at
  /// launch can come before the pack has loaded, so it may wait.
  final FutureOr<ContentSource> Function() _content;
  final ProfileWriter _writeProfile;

  @override
  Future<int> apply(
    StateSnapshot snapshot,
    StateWhy why, {
    required String playerId,
    required int sentAtElapsedMs,
    required int receivedAtElapsedMs,
  }) async {
    final hasRecord = await _hasOpenTripRecord(snapshot);
    final state = stateFromSnapshot(
      snapshot,
      hasTripRecord: (_) => hasRecord,
      content: await _content(),
    );
    final int dropped;
    if (why == StateWhy.account) {
      dropped = await _economy.adoptAccount(
        state,
        playerId: playerId,
        stateVersion: snapshot.stateVersion,
      );
    } else {
      await _economy.replaceFromServer(
        state,
        playerId: playerId,
        stateVersion: snapshot.stateVersion,
      );
      dropped = 0;
    }
    await _writeProfile(
      displayName: snapshot.displayName,
      driverLevel: snapshot.driverLevel,
    );
    // The server's clock at the request's midpoint (R15).
    await _economy.anchorOnServer(
      snapshot.serverTimeMs + (receivedAtElapsedMs - sentAtElapsedMs) ~/ 2,
      elapsedAtResponseMs: receivedAtElapsedMs,
    );
    return dropped;
  }

  Future<bool> _hasOpenTripRecord(StateSnapshot snapshot) async {
    final open = snapshot.openTrip;
    if (open == null) return false;
    try {
      return await _trips.has(TxnId.parse(open.startTxn));
    } on FormatException {
      return false;
    }
  }
}
