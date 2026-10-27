// The trip's replay record and its pending economy calls, on disk
// (contracts/trip-records.md), so a killed trip comes back exactly.
import 'dart:convert';

import 'package:content_models/content_models.dart';
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/core/economy/domain/txn_id.dart';

/// Every write returns true once it is on disk, or false when storage
/// failed it: then it stays queued and runs again before the next write.
abstract interface class TripRecords {
  /// Writes a new record with no commands, t_ms = 0.
  Future<bool> create(TripRecordHeader header);

  /// Appends one accepted command and moves the record's t_ms to its time,
  /// in one transaction.
  Future<bool> appendCommand(TxnId start, LoggedCommand command);

  /// Appends a `UseBooster` command and its pending economy call, in one
  /// transaction.
  Future<bool> appendBoosterUse(
    TxnId start,
    LoggedCommand command,
    TripIntent intent,
  );

  /// Saves the clock at a pause.
  Future<bool> saveClock(TxnId start, int tMs);

  Future<bool> deleteIntent(TxnId request);

  /// The full record and its pending intents, or null.
  Future<StoredTrip?> load(TxnId start);

  /// Whether a record for [start] is on this phone: the sync keeps the
  /// server's open trip only then (specs/011-m06-identity-sync, research
  /// R12). A read only.
  Future<bool> has(TxnId start);

  /// Deletes one record with its commands and intents.
  Future<bool> delete(TxnId start);

  /// Deletes every record except [keep] (null: all), with their commands
  /// and intents. Run at launch.
  Future<bool> deleteAllExcept(TxnId? keep);
}

/// What a record starts with.
final class TripRecordHeader {
  const TripRecordHeader({
    required this.startTxn,
    required this.tripId,
    required this.contentVersion,
    required this.definition,
    required this.seed,
    required this.params,
    required this.createdAtMs,
  });

  final TxnId startTxn;
  final String tripId;
  final int contentVersion;
  final TripDefinition definition;
  final int seed;
  final TripParams params;
  final int createdAtMs;
}

/// The economy call a `trip_intent` row holds. `use_booster` is the only
/// kind.
final class TripIntent {
  const TripIntent({
    required this.requestTxn,
    required this.startTxn,
    required this.booster,
  });

  static const useBoosterKind = 'use_booster';

  final TxnId requestTxn;
  final TxnId startTxn;
  final BoosterId booster;

  @override
  bool operator ==(Object other) =>
      other is TripIntent &&
      other.requestTxn == requestTxn &&
      other.startTxn == startTxn &&
      other.booster == booster;

  @override
  int get hashCode => Object.hash(requestTxn, startTxn, booster);
}

/// A record as stored: JSON text, decoded only when it is rebuilt.
final class StoredTrip {
  const StoredTrip({
    required this.startTxn,
    required this.tripId,
    required this.contentVersion,
    required this.definitionJson,
    required this.seed,
    required this.paramsJson,
    required this.commandJsons,
    required this.tMs,
    required this.createdAtMs,
    required this.intents,
  });

  final TxnId startTxn;
  final String tripId;
  final int contentVersion;
  final String definitionJson;
  final int seed;
  final String paramsJson;

  /// In `seq` order.
  final List<String> commandJsons;
  final int tMs;
  final int createdAtMs;
  final List<TripIntent> intents;

  /// M01's `ReplayRecord`. Throws [RebuildRefused] when the stored JSON
  /// doesn't read.
  ReplayRecord toReplayRecord() {
    try {
      return ReplayRecord.fromJson({
        'definition': jsonDecode(definitionJson),
        'seed': seed,
        'params': jsonDecode(paramsJson),
        'command_log': [for (final json in commandJsons) jsonDecode(json)],
        't_ms': tMs,
      });
    } on FormatException catch (e) {
      throw RebuildRefused('the stored record does not read: ${e.message}');
    }
  }
}
