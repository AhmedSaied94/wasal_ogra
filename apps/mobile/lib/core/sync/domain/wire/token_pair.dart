// The token answer of B02's three auth endpoints (B02 contracts/api.md
// "The token answer").
import 'package:wassal/core/sync/domain/wire/reader.dart';

/// `{player_id, access, refresh, access_expires_in, providers}`, plus
/// `created` from account creation. The tokens are opaque: nothing reads
/// their claims (B02 tokens.md).
final class TokenPair {
  const TokenPair({
    required this.playerId,
    required this.access,
    required this.refresh,
    required this.accessExpiresIn,
    required this.providers,
    this.created,
  });

  factory TokenPair.fromJson(Object? json) {
    final o = WireObject.of(json);
    return TokenPair(
      playerId: o.string('player_id'),
      access: o.string('access'),
      refresh: o.string('refresh'),
      accessExpiresIn: o.integer('access_expires_in'),
      providers: o.strings('providers'),
      created: o.has('created') ? o.boolean('created') : null,
    );
  }

  /// Whether [json] is a token answer rather than another `200` body (the
  /// link's `{player_id, providers}`).
  static bool isTokenPair(Map<String, Object?> json) =>
      json.containsKey('access') && json.containsKey('refresh');

  final String playerId;
  final String access;
  final String refresh;

  /// Seconds until [access] expires.
  final int accessExpiresIn;
  final List<String> providers;

  /// Account creation's: true for a new player, false for a returning one.
  final bool? created;

  /// The player only: the tokens never reach a log (FR-005).
  @override
  String toString() => 'TokenPair($playerId)';
}
