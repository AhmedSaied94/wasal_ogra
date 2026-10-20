// The command-log fingerprint (replay-and-fixtures.md §3): lowercase hex
// SHA-256 of the log's canonical JSON. Python computes the same with hashlib.
import 'package:test/test.dart';
import 'package:trip_engine/trip_engine.dart';

void main() {
  test('the empty log', () {
    expect(
      commandLogHash(const []),
      '4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945',
    );
  });

  test('a two-command log', () {
    expect(
      commandLogHash(const [
        LoggedCommand(33, Tap('p2')),
        LoggedCommand(1089, PickFromTray(100)),
      ]),
      '2fc7facd65d1ed083cda40c815e6044ed3e58e41fdbaf0d7448bdc8129e45ed7',
    );
  });

  test('any change to the log changes the fingerprint', () {
    final base = commandLogHash(const [LoggedCommand(33, Tap('p2'))]);
    expect(commandLogHash(const [LoggedCommand(66, Tap('p2'))]), isNot(base));
    expect(commandLogHash(const [LoggedCommand(33, Tap('p3'))]), isNot(base));
    expect(commandLogHash(const [LoggedCommand(33, Tap('p2'))]), base);
  });
}
