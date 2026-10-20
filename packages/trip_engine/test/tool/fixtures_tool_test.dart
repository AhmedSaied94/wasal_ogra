// tool/fixtures.dart (contracts/replay-and-fixtures.md §6): its exit codes,
// and that bad paths are reported, not thrown.
import 'dart:io';

import 'package:test/test.dart';

import '../../tool/fixtures.dart' as tool;

const _fixture = '../../fixtures/parity/core__exact_change.json';

void main() {
  late Directory temp;
  setUp(() => temp = Directory.systemTemp.createTempSync('fixtures_tool'));
  tearDown(() => temp.deleteSync(recursive: true));

  (int, String) run(List<String> args, {String? dir}) {
    final out = StringBuffer();
    final err = StringBuffer();
    final code = dir == null
        ? tool.run(args, out, err)
        : tool.run(args, out, err, dir: dir);
    return (code, '$out$err');
  }

  String copy() {
    final path = '${temp.path}/core__exact_change.json';
    File(_fixture).copySync(path);
    return path;
  }

  test('a usage error exits 64', () {
    expect(run([]).$1, 64);
    expect(run(['update']).$1, 64);
    expect(run(['show', 'a.json', 'b.json']).$1, 64);
  });

  test('check passes on a good fixture, update leaves it unchanged', () {
    final path = copy();
    expect(run(['check', path]), (0, '1 fixtures checked, 0 differ\n'));
    expect(run(['update', path]), (0, 'unchanged $path\n'));
  });

  test('show prints the events and the result', () {
    final (code, out) = run(['show', copy()]);
    expect(code, 0);
    expect(out, contains('ChangeDelivered '));
    expect(out.trim().split('\n').last, startsWith('result {'));
  });

  test('a missing file is reported by every command, not thrown', () {
    final missing = '${temp.path}/none.json';
    for (final command in ['check', 'update', 'show']) {
      final (code, out) = run([command, missing]);
      expect(code, 1, reason: command);
      expect(out, contains('$missing: unreadable'), reason: command);
    }
  });

  test('a missing or empty fixture directory fails check', () {
    expect(run(['check'], dir: '${temp.path}/nowhere'), (
      1,
      'no fixtures in ${temp.path}/nowhere (run this in packages/trip_engine)\n',
    ));
    expect(run(['check'], dir: temp.path), (
      1,
      'no fixtures in ${temp.path} (run this in packages/trip_engine)\n',
    ));
  });

  test('a malformed fixture is reported as malformed', () {
    final path = '${temp.path}/core__bad.json';
    File(path).writeAsStringSync('{"definition": 1}');
    final (code, out) = run(['check', path]);
    expect(code, 1);
    expect(out, contains('$path: malformed'));
  });
}
