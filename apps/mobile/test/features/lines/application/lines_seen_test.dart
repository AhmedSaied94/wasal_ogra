// The seen set (specs/014-m09-lines-vehicles, research R8): the
// preference's round trip and the first read.
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/features/lines/application/lines_seen.dart';

void main() {
  test('sorted and comma-joined, both ways', () {
    const keys = {'vehicle:micro_old', 'line:line_gamaa', 'story:line_hay.20'};
    final encoded = LinesSeenNotifier.encode(keys);
    expect(encoded, 'line:line_gamaa,story:line_hay.20,vehicle:micro_old');
    expect(LinesSeenNotifier.decode(encoded), keys);
    expect(LinesSeenNotifier.decode(''), isEmpty);
  });

  test('the key is a listed preference', () {
    expect(LinesSeenNotifier.key, 'pref.lines_seen');
  });
}
