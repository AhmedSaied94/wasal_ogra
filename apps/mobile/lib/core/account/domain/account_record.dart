// The rows `DriftAccountStore` keeps (data-model.md "`account`",
// "`server_info`"), as the rest of the app reads them.
import 'dart:convert';

import 'package:wassal/core/account/domain/account.dart';
import 'package:wassal/core/sync/domain/wire/bootstrap.dart';

/// The `account` row.
final class AccountRecord {
  const AccountRecord({
    required this.status,
    required this.providers,
    required this.updatedAtMs,
    this.playerId,
    this.displayName,
    this.driverLevel,
    this.firstOpenAtMs,
    this.restoredAtMs,
  });

  static const initial = AccountRecord(
    status: AccountStatus.none,
    providers: [],
    updatedAtMs: 0,
  );

  final AccountStatus status;
  final String? playerId;
  final List<String> providers;
  final String? displayName;
  final int? driverLevel;

  /// Trusted time of the first open with M06; set once.
  final int? firstOpenAtMs;

  /// Trusted time a returning player's state was first taken (research R6).
  final int? restoredAtMs;
  final int updatedAtMs;

  /// The profile, once there is a player.
  Profile? get profile => switch (playerId) {
    final id? => Profile(
      playerId: id,
      providers: providers.toSet(),
      displayName: displayName,
      driverLevel: driverLevel,
    ),
    null => null,
  };

  @override
  String toString() => 'AccountRecord(${status.wire}, $playerId)';
}

/// The `server_info` row: the last bootstrap's blocks and the comeback
/// lock (research R15, R16). Readable offline (FR-015).
final class ServerInfo {
  const ServerInfo({
    required this.comebackClaimable,
    this.receivedAtMs,
    this.serverTimeMs,
    this.stateVersion,
    this.contentVersion,
    this.clientJson,
    this.entitlementsJson,
    this.dailyJson,
    this.comebackClaimedAtMs,
    this.comebackAnsweredAtMs,
  });

  static const empty = ServerInfo(comebackClaimable: false);

  /// Trusted time the last bootstrap arrived; null before the first.
  final int? receivedAtMs;
  final int? serverTimeMs;
  final int? stateVersion;
  final int? contentVersion;

  /// Each block as canonical JSON.
  final String? clientJson;
  final String? entitlementsJson;
  final String? dailyJson;
  final bool comebackClaimable;
  final int? comebackClaimedAtMs;
  final int? comebackAnsweredAtMs;

  ClientBlock? get client => _read(clientJson, ClientBlock.fromJson);

  /// Neutral before the first bootstrap.
  Entitlements get entitlements =>
      _read(entitlementsJson, Entitlements.fromJson) ?? Entitlements.neutral;

  DailyBlock? get daily => _read(dailyJson, DailyBlock.fromJson);

  static T? _read<T>(String? text, T Function(Object? json) read) =>
      text == null ? null : read(jsonDecode(text));
}
