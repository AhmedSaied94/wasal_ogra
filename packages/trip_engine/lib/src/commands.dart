// The 13 player commands (FR-050), their wire form `[t_ms, "Name", ...args]`
// (replay-and-fixtures.md §1), and how a command is refused.
import 'package:content_models/content_models.dart';

import 'clock.dart';
import 'events.dart';
import 'wire.dart';

sealed class Command {
  const Command();

  /// The wire name, such as `PickFromTray`.
  String get name;

  /// The positional wire arguments.
  List<Object> get arguments;

  @override
  String toString() => '$name$arguments';
}

/// Moves one piece of [denomination] from the tray to the hand.
final class PickFromTray extends Command {
  const PickFromTray(this.denomination);

  final int denomination;

  @override
  String get name => 'PickFromTray';

  @override
  List<Object> get arguments => [denomination];
}

/// Puts the hand back in the tray.
final class ReturnHand extends Command {
  const ReturnHand();

  @override
  String get name => 'ReturnHand';

  @override
  List<Object> get arguments => const [];
}

/// Sends the hand as change to [passengerId].
final class SendHand extends Command {
  const SendHand(this.passengerId);

  final String passengerId;

  @override
  String get name => 'SendHand';

  @override
  List<Object> get arguments => [passengerId];
}

final class UndoLastSend extends Command {
  const UndoLastSend();

  @override
  String get name => 'UndoLastSend';

  @override
  List<Object> get arguments => const [];
}

final class Tap extends Command {
  const Tap(this.passengerId);

  final String passengerId;

  @override
  String get name => 'Tap';

  @override
  List<Object> get arguments => [passengerId];
}

/// Answers [passengerId]'s claim: insist they haven't paid, or accept it.
final class ResolveClaim extends Command {
  const ResolveClaim(this.passengerId, {required this.insist});

  final String passengerId;
  final bool insist;

  @override
  String get name => 'ResolveClaim';

  @override
  List<Object> get arguments => [passengerId, insist];
}

/// Answers dispute [disputeId] (its event index): [paidPassengerId] is the
/// one who paid.
final class ResolveDispute extends Command {
  const ResolveDispute(this.disputeId, this.paidPassengerId);

  final int disputeId;
  final String paidPassengerId;

  @override
  String get name => 'ResolveDispute';

  @override
  List<Object> get arguments => [disputeId, paidPassengerId];
}

final class ResolveChangeRequest extends Command {
  const ResolveChangeRequest(this.passengerId, {required this.agree});

  final String passengerId;
  final bool agree;

  @override
  String get name => 'ResolveChangeRequest';

  @override
  List<Object> get arguments => [passengerId, agree];
}

/// «حد معاه فكة؟»: breaks one [denomination] note into smaller pieces.
final class RequestBreak extends Command {
  const RequestBreak(this.denomination);

  final int denomination;

  @override
  String get name => 'RequestBreak';

  @override
  List<Object> get arguments => [denomination];
}

final class CollectDropped extends Command {
  const CollectDropped(this.tokenId);

  final int tokenId;

  @override
  String get name => 'CollectDropped';

  @override
  List<Object> get arguments => [tokenId];
}

/// Uses an in-trip booster: `change_bag`, `wake_all`, `ledger_peek` or
/// `traffic_jam`.
final class UseBooster extends Command {
  const UseBooster(this.booster);

  final BoosterId booster;

  @override
  String get name => 'UseBooster';

  @override
  List<Object> get arguments => [wireName(booster)];
}

final class Revive extends Command {
  const Revive();

  @override
  String get name => 'Revive';

  @override
  List<Object> get arguments => const [];
}

final class Abandon extends Command {
  const Abandon();

  @override
  String get name => 'Abandon';

  @override
  List<Object> get arguments => const [];
}

/// One entry of the command log: a command and the clock when it applied.
final class LoggedCommand {
  const LoggedCommand(this.tMs, this.command);

  /// Decodes `[t_ms, "Name", ...args]`. Throws [FormatException] for an
  /// unknown name, the wrong arguments, or a `t_ms` that isn't a
  /// non-negative multiple of [stepMs].
  factory LoggedCommand.fromJson(Object? json) {
    if (json is! List<Object?> || json.length < 2) {
      throw FormatException(
        'a logged command is [t_ms, "Name", ...args]: $json',
      );
    }
    final tMs = json[0];
    if (tMs is! int || tMs < 0 || tMs % stepMs != 0) {
      throw FormatException(
        't_ms must be a non-negative multiple of $stepMs: $json',
      );
    }
    final name = json[1];
    final decode = name is String ? _decoders[name] : null;
    if (decode == null) throw FormatException('unknown command: $json');
    final command = decode(json.sublist(2));
    if (command == null) {
      throw FormatException('bad arguments for $name: $json');
    }
    return LoggedCommand(tMs, command);
  }

  final int tMs;
  final Command command;

  List<Object> toJson() => [tMs, command.name, ...command.arguments];

  @override
  String toString() => '${toJson()}';
}

/// Decodes a whole command log. Throws [FormatException].
List<LoggedCommand> decodeCommandLog(Object? json) {
  if (json is! List<Object?>) {
    throw const FormatException('a command log is a list');
  }
  return [for (final entry in json) LoggedCommand.fromJson(entry)];
}

final _decoders = <String, Command? Function(List<Object?>)>{
  'PickFromTray': (a) => switch (a) {
    [final int denomination] => PickFromTray(denomination),
    _ => null,
  },
  'ReturnHand': (a) => a.isEmpty ? const ReturnHand() : null,
  'SendHand': (a) => switch (a) {
    [final String passenger] => SendHand(passenger),
    _ => null,
  },
  'UndoLastSend': (a) => a.isEmpty ? const UndoLastSend() : null,
  'Tap': (a) => switch (a) {
    [final String passenger] => Tap(passenger),
    _ => null,
  },
  'ResolveClaim': (a) => switch (a) {
    [final String passenger, final bool insist] => ResolveClaim(
      passenger,
      insist: insist,
    ),
    _ => null,
  },
  'ResolveDispute': (a) => switch (a) {
    [final int dispute, final String paid] => ResolveDispute(dispute, paid),
    _ => null,
  },
  'ResolveChangeRequest': (a) => switch (a) {
    [final String passenger, final bool agree] => ResolveChangeRequest(
      passenger,
      agree: agree,
    ),
    _ => null,
  },
  'RequestBreak': (a) => switch (a) {
    [final int denomination] => RequestBreak(denomination),
    _ => null,
  },
  'CollectDropped': (a) => switch (a) {
    [final int token] => CollectDropped(token),
    _ => null,
  },
  'UseBooster': (a) => switch (a) {
    [final booster] => switch (byWire(BoosterId.values, booster)) {
      final id? => UseBooster(id),
      null => null,
    },
    _ => null,
  },
  'Revive': (a) => a.isEmpty ? const Revive() : null,
  'Abandon': (a) => a.isEmpty ? const Abandon() : null,
};

/// Why a command was refused (contracts/engine-api.md).
enum RejectionCode {
  wrongStatus,
  commandLimit,
  badArgument,
  trayEmpty,
  handEmpty,
  notAboard,
  undoUnavailable,
  noEffect,
  noChoice,
  cannotMakeChange,
  breakLimit,
  boosterLimit,
  notRevivable;

  String get wire => wireName(this);
}

/// A refused command. The message is English and for developers only;
/// player text comes from the app's ARB file, keyed by [code].
final class Rejection {
  const Rejection(this.code, this.message);

  final RejectionCode code;
  final String message;

  @override
  String toString() => 'Rejection(${code.wire}: $message)';
}

sealed class CommandOutcome {
  const CommandOutcome();
}

final class Accepted extends CommandOutcome {
  const Accepted(this.events);

  final List<DomainEvent> events;
}

final class Rejected extends CommandOutcome {
  const Rejected(this.rejection);

  final Rejection rejection;
}
