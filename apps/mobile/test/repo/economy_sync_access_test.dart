import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_source.dart';

// The calls that apply the server's answers are the sync's alone, never a
// screen's (specs/011-m06-identity-sync FR-022, research R20,
// contracts/ci-checks.md "Sync-only economy calls").

const _allowed = ['lib/core/sync/', 'lib/core/account/', 'lib/core/economy/'];

final _syncOnly = RegExp(
  r'\b(?:economySyncProvider|EconomySync|applyAnswer|replaceFromServer|'
  r'adoptAccount|setAside|grantComebackGift)\b',
);

/// Lines of [source] that reach the economy's sync calls.
List<String> syncReaches(String source) {
  final lines = stripComments(source).split('\n');
  return [
    for (var i = 0; i < lines.length; i++)
      if (_syncOnly.hasMatch(lines[i])) '${i + 1}: ${lines[i].trim()}',
  ];
}

void main() {
  test('only the sync and the account reach EconomySync', () {
    final violations = [
      for (final file in libDartFiles())
        if (!_allowed.any(file.path.replaceAll(r'\', '/').startsWith))
          for (final hit in syncReaches(file.readAsStringSync()))
            '${file.path}:$hit',
    ];
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test('the scan catches every sync call and ignores the rest', () {
    for (final line in [
      'ref.read(economySyncProvider)',
      'final EconomySync sync;',
      'await sync.applyAnswer(a, batch: b, playerId: p);',
      'economy.replaceFromServer(s, playerId: p, stateVersion: 1);',
      'economy.adoptAccount(s, playerId: p, stateVersion: 1);',
      'economy.setAside({id: reason});',
      'economy.grantComebackGift(id);',
    ]) {
      expect(syncReaches(line), hasLength(1), reason: line);
    }
    expect(syncReaches('// economy.applyAnswer(a)'), isEmpty);
    expect(syncReaches('economy.buy(id, kind: k, skuId: s);'), isEmpty);
    expect(syncReaches('final asideFrom = 1;'), isEmpty);
  });
}
