// Commands on the wire: `[t_ms, "Name", ...args]` (replay-and-fixtures.md §1).
import 'dart:convert';

import 'package:content_models/content_models.dart';
import 'package:test/test.dart';
import 'package:trip_engine/trip_engine.dart';

final _cases = <(Command, List<Object>)>[
  (const PickFromTray(100), [330, 'PickFromTray', 100]),
  (const ReturnHand(), [363, 'ReturnHand']),
  (const SendHand('p2'), [396, 'SendHand', 'p2']),
  (const UndoLastSend(), [429, 'UndoLastSend']),
  (const Tap('p1'), [462, 'Tap', 'p1']),
  (const ResolveClaim('p4', insist: true), [990, 'ResolveClaim', 'p4', true]),
  (const ResolveDispute(2, 'p1'), [1650, 'ResolveDispute', 2, 'p1']),
  (
    const ResolveChangeRequest('p3', agree: false),
    [1683, 'ResolveChangeRequest', 'p3', false],
  ),
  (const RequestBreak(5000), [1716, 'RequestBreak', 5000]),
  (const CollectDropped(7), [1749, 'CollectDropped', 7]),
  (const UseBooster(BoosterId.wakeAll), [2013, 'UseBooster', 'wake_all']),
  (const Revive(), [2046, 'Revive']),
  (const Abandon(), [2079, 'Abandon']),
];

void main() {
  test('there are 13 commands', () {
    expect({for (final (_, wire) in _cases) wire[1]}, hasLength(13));
  });

  for (final (command, wire) in _cases) {
    test('${wire[1]} encodes and decodes', () {
      final logged = LoggedCommand(wire[0] as int, command);
      expect(logged.toJson(), wire);
      final decoded = LoggedCommand.fromJson(jsonDecode(jsonEncode(wire)));
      expect(decoded.tMs, wire[0]);
      expect(decoded.command.runtimeType, command.runtimeType);
      expect(decoded.toJson(), wire);
      expect(decoded.command.name, wire[1]);
    });
  }

  test('a booster outside the in-trip four still decodes, for the engine to reject', () {
    final decoded = LoggedCommand.fromJson([33, 'UseBooster', 'revive']);
    expect((decoded.command as UseBooster).booster, BoosterId.revive);
  });

  test('a malformed entry is a FormatException', () {
    for (final bad in <Object?>[
      'Tap',
      <Object?>[],
      [33],
      [33, 'Fly'],
      [33, 'Tap'],
      [33, 'Tap', 'p1', 'p2'],
      [33, 'Tap', 1],
      [33, 'PickFromTray', '100'],
      [33, 'PickFromTray', 100.0],
      [33, 'ResolveClaim', 'p1', 'yes'],
      [33, 'ResolveDispute', '2', 'p1'],
      [33, 'UseBooster', 'rocket'],
      [-33, 'ReturnHand'],
      [34, 'ReturnHand'],
      ['33', 'ReturnHand'],
      [33.0, 'ReturnHand'],
      [33, 7],
    ]) {
      expect(
        () => LoggedCommand.fromJson(bad),
        throwsFormatException,
        reason: '$bad',
      );
    }
  });

  test('a log decodes as a list of entries', () {
    final log = decodeCommandLog(
      jsonDecode('[[33,"Tap","p2"],[1089,"PickFromTray",100]]'),
    );
    expect(log.map((entry) => entry.toJson()).toList(), [
      [33, 'Tap', 'p2'],
      [1089, 'PickFromTray', 100],
    ]);
    expect(() => decodeCommandLog({'not': 'a list'}), throwsFormatException);
  });

  test('rejection codes have the engine-api.md wire names', () {
    expect(RejectionCode.values.map((code) => code.wire).toList(), [
      'wrong_status',
      'command_limit',
      'bad_argument',
      'tray_empty',
      'hand_empty',
      'not_aboard',
      'undo_unavailable',
      'no_effect',
      'no_choice',
      'cannot_make_change',
      'break_limit',
      'booster_limit',
      'not_revivable',
    ]);
  });
}
