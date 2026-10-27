// The account's values (specs/011-m06-identity-sync/data-model.md "Domain
// values"). Pure Dart: the domain-imports guard keeps it so.
import 'dart:convert';

final _uuidV4 = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

/// One install's id: a lowercase version-4 UUID, the device's credential
/// for account creation (research R1). Sent nowhere else, and never logged
/// (FR-002).
final class InstallId {
  const InstallId._(this.value);

  /// Throws [FormatException] unless [value] is a lowercase UUIDv4.
  factory InstallId.parse(String value) {
    if (!_uuidV4.hasMatch(value)) {
      throw const FormatException('not a lowercase UUIDv4');
    }
    return InstallId._(value);
  }

  /// The id in [value], or null.
  static InstallId? tryParse(String? value) =>
      value != null && _uuidV4.hasMatch(value) ? InstallId._(value) : null;

  final String value;

  @override
  bool operator ==(Object other) => other is InstallId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  /// Never the id itself.
  @override
  String toString() => 'InstallId(…)';
}

/// The tokens of one sign-in, stored together in one secure-storage write
/// (research R2). [accessExpiresAtMs] is trusted time.
final class Session {
  const Session({
    required this.playerId,
    required this.access,
    required this.refresh,
    required this.accessExpiresAtMs,
  });

  /// The session in [text], or null when it isn't one this app wrote.
  static Session? tryDecode(String? text) {
    if (text == null) return null;
    try {
      return switch (jsonDecode(text)) {
        {
          'player_id': final String playerId,
          'access': final String access,
          'refresh': final String refresh,
          'access_expires_at_ms': final int expiresAt,
        } =>
          Session(
            playerId: playerId,
            access: access,
            refresh: refresh,
            accessExpiresAtMs: expiresAt,
          ),
        _ => null,
      };
    } on FormatException {
      return null;
    }
  }

  final String playerId;
  final String access;
  final String refresh;
  final int accessExpiresAtMs;

  String encode() => jsonEncode({
    'player_id': playerId,
    'access': access,
    'refresh': refresh,
    'access_expires_at_ms': accessExpiresAtMs,
  });

  /// The player only: tokens never reach a log or an error report (FR-005).
  @override
  String toString() => 'Session($playerId)';
}

/// The account's state (data-model.md "The account").
enum AccountStatus {
  none('none'),
  active('active'),

  /// Final for this feature: B09 and M14 decide what follows.
  deleted('deleted');

  const AccountStatus(this.wire);

  final String wire;

  static AccountStatus of(String wire) =>
      values.firstWhere((s) => s.wire == wire, orElse: () => none);
}

/// What the server last said of the player (FR-009).
final class Profile {
  const Profile({
    required this.playerId,
    required this.providers,
    this.displayName,
    this.driverLevel,
  });

  final String playerId;

  /// Linked providers: `google`; `apple` in phase 3.
  final Set<String> providers;
  final String? displayName;
  final int? driverLevel;

  @override
  bool operator ==(Object other) =>
      other is Profile &&
      other.playerId == playerId &&
      other.providers.length == providers.length &&
      other.providers.containsAll(providers) &&
      other.displayName == displayName &&
      other.driverLevel == driverLevel;

  @override
  int get hashCode => Object.hash(
    playerId,
    Object.hashAllUnordered(providers),
    displayName,
    driverLevel,
  );

  @override
  String toString() => 'Profile($playerId, $providers)';
}

/// How the first open of an install went (research R6). M07 routes by it.
enum FirstOpenOutcome {
  /// The server made a new player.
  newPlayer,

  /// A returning player's state was taken before boot handed over.
  restored,

  /// No network, or the account couldn't be made.
  offline,

  /// Boot stopped waiting after `firstOpenWait`.
  timedOut,

  /// A later launch.
  notFirstOpen,
}
