// The only code that writes the `account` and `server_info` tables
// (specs/011-m06-identity-sync, data-model.md "Tables (schema v3)").
// `economy_writes_test.dart` keeps every other file out. Each write is one
// transaction; the rows are read once at startup, and kept in memory so
// the providers read them synchronously and offline (FR-015).
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:wassal/core/account/domain/account.dart';
import 'package:wassal/core/account/domain/account_record.dart';
import 'package:wassal/core/storage/app_database.dart';

final class DriftAccountStore {
  DriftAccountStore(this._db, {required this._nowMs});

  final AppDatabase _db;

  /// Trusted time, for `updated_at_ms`.
  final int Function() _nowMs;

  AccountRecord _account = AccountRecord.initial;
  ServerInfo _info = ServerInfo.empty;

  /// The `account` row, as of the last [load] or write.
  AccountRecord get account => _account;

  /// The `server_info` row, as of the last [load] or write.
  ServerInfo get serverInfo => _info;

  Future<void> load() async {
    _account = _accountOf(await _db.select(_db.accountTable).getSingle());
    _info = _infoOf(await _db.select(_db.serverInfoTable).getSingle());
  }

  /// Sets `first_open_at_ms` unless it is already set.
  Future<void> markFirstOpen(int atMs) => _writeAccount(
    (row) => row.firstOpenAtMs != null
        ? null
        : AccountTableCompanion(firstOpenAtMs: Value(atMs)),
  );

  /// A token answer: the account is active for [playerId], with
  /// [providers].
  Future<void> signedIn({
    required String playerId,
    required List<String> providers,
  }) => _writeAccount(
    (_) => AccountTableCompanion(
      status: Value(AccountStatus.active.wire),
      playerId: Value(playerId),
      providers: Value(jsonEncode(providers)),
    ),
  );

  /// What the server last said of the player. Null arguments keep the
  /// stored value.
  Future<void> setProfile({
    List<String>? providers,
    String? displayName,
    int? driverLevel,
  }) => _writeAccount(
    (_) => AccountTableCompanion(
      providers: providers == null
          ? const Value.absent()
          : Value(jsonEncode(providers)),
      displayName: displayName == null
          ? const Value.absent()
          : Value(displayName),
      driverLevel: driverLevel == null
          ? const Value.absent()
          : Value(driverLevel),
    ),
  );

  /// `403 account_deleted`: final for this feature (research R7).
  Future<void> markDeleted() => _writeAccount(
    (_) => AccountTableCompanion(status: Value(AccountStatus.deleted.wire)),
  );

  /// A returning player's state was taken (research R6).
  Future<void> markRestored(int atMs) =>
      _writeAccount((_) => AccountTableCompanion(restoredAtMs: Value(atMs)));

  /// The last bootstrap: each block as JSON with sorted keys (research
  /// R15). Unlike content, the server's blocks may hold nulls.
  Future<void> saveBootstrap({
    required int receivedAtMs,
    required int serverTimeMs,
    required int stateVersion,
    required int? contentVersion,
    required Object? client,
    required Object? entitlements,
    required Object? daily,
    required bool comebackClaimable,
  }) => _writeInfo(
    ServerInfoTableCompanion(
      receivedAtMs: Value(receivedAtMs),
      serverTimeMs: Value(serverTimeMs),
      stateVersion: Value(stateVersion),
      contentVersion: Value(contentVersion),
      client: Value(_sortedJson(client)),
      entitlements: Value(_sortedJson(entitlements)),
      daily: Value(_sortedJson(daily)),
      comebackClaimable: Value(comebackClaimable ? 1 : 0),
    ),
  );

  /// A comeback claim was made (research R16).
  Future<void> markComebackClaimed(int atMs) =>
      _writeInfo(ServerInfoTableCompanion(comebackClaimedAtMs: Value(atMs)));

  /// The claim's operation was answered.
  Future<void> markComebackAnswered(int atMs) =>
      _writeInfo(ServerInfoTableCompanion(comebackAnsweredAtMs: Value(atMs)));

  /// Writes what [change] gives for the current row, with `updated_at_ms`,
  /// in one transaction. A null change writes nothing.
  Future<void> _writeAccount(
    AccountTableCompanion? Function(AccountRow row) change,
  ) async {
    final row = await _db.transaction(() async {
      final current = await _db.select(_db.accountTable).getSingle();
      final companion = change(current);
      if (companion == null) return current;
      await _db
          .update(_db.accountTable)
          .write(companion.copyWith(updatedAtMs: Value(_nowMs())));
      return _db.select(_db.accountTable).getSingle();
    });
    _account = _accountOf(row);
  }

  Future<void> _writeInfo(ServerInfoTableCompanion companion) async {
    final row = await _db.transaction(() async {
      await _db.update(_db.serverInfoTable).write(companion);
      return _db.select(_db.serverInfoTable).getSingle();
    });
    _info = _infoOf(row);
  }

  static AccountRecord _accountOf(AccountRow row) => AccountRecord(
    status: AccountStatus.of(row.status),
    playerId: row.playerId,
    providers: (jsonDecode(row.providers) as List<Object?>)
        .whereType<String>()
        .toList(growable: false),
    displayName: row.displayName,
    driverLevel: row.driverLevel,
    firstOpenAtMs: row.firstOpenAtMs,
    restoredAtMs: row.restoredAtMs,
    updatedAtMs: row.updatedAtMs,
  );

  static ServerInfo _infoOf(ServerInfoRow row) => ServerInfo(
    receivedAtMs: row.receivedAtMs,
    serverTimeMs: row.serverTimeMs,
    stateVersion: row.stateVersion,
    contentVersion: row.contentVersion,
    clientJson: row.client,
    entitlementsJson: row.entitlements,
    dailyJson: row.daily,
    comebackClaimable: row.comebackClaimable == 1,
    comebackClaimedAtMs: row.comebackClaimedAtMs,
    comebackAnsweredAtMs: row.comebackAnsweredAtMs,
  );
}

/// [value] as JSON with every object's keys sorted, so the same block is
/// always the same text.
String _sortedJson(Object? value) => jsonEncode(_sorted(value));

Object? _sorted(Object? value) => switch (value) {
  final Map<String, Object?> map => {
    for (final key in map.keys.toList()..sort()) key: _sorted(map[key]),
  },
  final List<Object?> list => [for (final item in list) _sorted(item)],
  _ => value,
};
