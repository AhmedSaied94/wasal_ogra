// `POST /v1/auth/link` (B02 contracts/api.md): its `200` without tokens, and
// the details of its `409 provider_in_use`.
import 'package:wassal/core/sync/domain/wire/reader.dart';

/// `{player_id, providers}`: Google linked to the current player.
final class LinkResult {
  const LinkResult({required this.playerId, required this.providers});

  factory LinkResult.fromJson(Object? json) {
    final o = WireObject.of(json);
    return LinkResult(
      playerId: o.string('player_id'),
      providers: o.strings('providers'),
    );
  }

  final String playerId;
  final List<String> providers;
}

/// One side of a conflict: what the server holds now, nothing personal.
final class ConflictSummary {
  const ConflictSummary({
    required this.driverLevel,
    required this.chapterId,
    required this.bonat,
    this.playerId,
  });

  factory ConflictSummary.fromJson(Object? json, String path) {
    final o = WireObject.of(json, path);
    return ConflictSummary(
      driverLevel: o.integer('driver_level'),
      chapterId: o.string('chapter_id'),
      bonat: o.integer('bonat'),
      playerId: o.optionalString('player_id'),
    );
  }

  final int driverLevel;
  final String chapterId;
  final int bonat;

  /// The existing player's, which the retry sends back. Null for the
  /// current one.
  final String? playerId;
}

/// `409 provider_in_use`'s `details`.
({ConflictSummary current, ConflictSummary existing}) conflictOf(
  Map<String, Object?> details,
) {
  final existing = ConflictSummary.fromJson(details['existing'], 'existing');
  if (existing.playerId == null) {
    throw const WireFormatException('existing.player_id is missing');
  }
  return (
    current: ConflictSummary.fromJson(details['current'], 'current'),
    existing: existing,
  );
}
