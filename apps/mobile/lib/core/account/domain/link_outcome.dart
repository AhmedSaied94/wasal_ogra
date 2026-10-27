// What a link request came to (contracts/account.md "Link outcomes",
// research R8). M14 builds its screens on these.
import 'package:wassal/core/sync/domain/wire/link.dart';

export 'package:wassal/core/sync/domain/wire/link.dart' show ConflictSummary;

/// The player's answer to a conflict.
enum LinkResolve {
  keepCurrent('keep_current'),
  switchToExisting('switch_to_existing');

  const LinkResolve(this.wire);

  final String wire;
}

/// Every outcome says whether the queue was empty before the link was sent,
/// so M14 can warn that the summaries may be behind.
sealed class LinkOutcome {
  const LinkOutcome({required this.flushed});

  final bool flushed;
}

final class Linked extends LinkOutcome {
  const Linked(this.providers, {required super.flushed});

  final Set<String> providers;
}

/// Google belongs to another player: M14 shows both, and the retry sends
/// [existing]'s player id back.
final class Conflict extends LinkOutcome {
  const Conflict(this.current, this.existing, {required super.flushed});

  final ConflictSummary current;
  final ConflictSummary existing;
}

final class ProviderAlreadyLinked extends LinkOutcome {
  const ProviderAlreadyLinked({required super.flushed});
}

/// Google's token failed a check: `expired`, `audience`, `issuer`,
/// `signature` or `malformed`. The session is never renewed for it.
final class GoogleTokenRefused extends LinkOutcome {
  const GoogleTokenRefused(this.reason, {required super.flushed});

  final String reason;
}

final class LinkUnreachable extends LinkOutcome {
  const LinkUnreachable({required super.flushed});
}

final class LinkFailed extends LinkOutcome {
  const LinkFailed(this.code, {required super.flushed});

  final String code;
}
