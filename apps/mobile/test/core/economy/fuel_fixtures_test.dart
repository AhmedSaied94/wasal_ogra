import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/economy/domain/economy_state.dart';
import 'package:wassal/core/economy/domain/fuel.dart';

// The fuel cases the server and the app share (fixtures/economy/fuel.json,
// B03 research R15). The `both` cases replay here through M05's own
// functions; the backend replays every case through its `fuel.py`. If a case
// fails here, the fixture or M05 is wrong: fix the one that is, never loosen
// the case.

const _fixture = '../../fixtures/economy/fuel.json';

int _ms(String stamp) => DateTime.parse(stamp).millisecondsSinceEpoch;

int? _maybeMs(Object? stamp) => stamp == null ? null : _ms(stamp as String);

String? _stamp(int? ms) => ms == null
    ? null
    : DateTime.fromMillisecondsSinceEpoch(
        ms,
        isUtc: true,
      ).toIso8601String().replaceFirst('.000Z', 'Z');

Map<String, Object?> _shown(FuelState s, {required bool accepted}) => {
  'liters': s.liters,
  'counted_from': _stamp(s.countedFromMs),
  'unlimited_until': _stamp(s.unlimitedUntilMs),
  'accepted': accepted,
};

/// What M05's rules give after each step of [kase].
List<Map<String, Object?>> _replay(Map<String, Object?> kase) {
  final settings = kase['settings']! as Map<String, Object?>;
  final initial = kase['initial']! as Map<String, Object?>;
  final regenMs = regenMsOf(settings['regen_minutes']! as int);
  var max = settings['max']! as int;
  var s = FuelState(
    liters: initial['liters']! as int,
    countedFromMs: _ms(initial['counted_from']! as String),
    unlimitedUntilMs: _maybeMs(initial['unlimited_until']),
  );
  final results = <Map<String, Object?>>[];
  for (final step in (kase['steps']! as List).cast<Map<String, Object?>>()) {
    final t = _ms(step['t']! as String);
    final r = regenerate(s, t, max: max, regenMs: regenMs);
    switch (step['op']) {
      case 'trip_start':
        if (step['mode'] == 'unlimited') {
          if (!isUnlimited(r, t)) {
            results.add({
              ..._shown(s, accepted: false),
              'reason': 'not_eligible',
            });
            continue;
          }
          s = r;
        } else {
          s = spendOne(r, t, max: max);
        }
        results.add(_shown(s, accepted: true));
      case 'refill':
        final filled = fillToMax(r, t, max: max);
        if (filled == null) {
          results.add({..._shown(s, accepted: false), 'reason': 'tank_full'});
          continue;
        }
        s = filled;
        results.add(_shown(s, accepted: true));
      case 'unlimited_1h':
        s = extendUnlimited(r, t);
        results.add(_shown(s, accepted: true));
      case 'set_max':
        max = step['max']! as int;
        results.add(_shown(s, accepted: true));
      case 'read':
        results.add(_shown(r, accepted: true));
      default:
        fail('a step M05 has no rule for: ${step['op']}');
    }
  }
  return results;
}

void main() {
  final document =
      jsonDecode(File(_fixture).readAsStringSync()) as Map<String, Object?>;
  final cases = (document['cases']! as List)
      .cast<Map<String, Object?>>()
      .where((kase) => kase['scope'] == 'both')
      .toList();

  test('the fixture has cases for the app', () {
    expect(cases, isNotEmpty);
  });

  for (final kase in cases) {
    test(kase['name']! as String, () {
      expect(_replay(kase), kase['expected']);
    });
  }
}
