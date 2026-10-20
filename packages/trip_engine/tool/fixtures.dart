// The parity fixture tool (contracts/replay-and-fixtures.md §6). Run in
// packages/trip_engine:
//
//   fvm dart run tool/fixtures.dart check [file…]   exit 1 on a difference
//   fvm dart run tool/fixtures.dart update <file>…  rewrite expected_result
//   fvm dart run tool/fixtures.dart show <file>     the replay's events
import 'dart:convert';
import 'dart:io';

import 'package:trip_engine/src/replay.dart' show replayEngine;
import 'package:trip_engine/trip_engine.dart';

const fixturesDir = '../../fixtures/parity';

const _usage = '''
usage: fixtures.dart check [file…]
       fixtures.dart update <file>…
       fixtures.dart show <file>''';

void main(List<String> args) {
  exitCode = run(args, stdout, stderr);
}

/// Runs one command and returns the exit code: 0, 1 when a fixture differs
/// or fails or there are none, or 64 for a usage error. `check` with no
/// files checks every fixture in [dir].
int run(
  List<String> args,
  StringSink out,
  StringSink err, {
  String dir = fixturesDir,
}) {
  final files = args.skip(1).toList();
  switch (args.firstOrNull) {
    case 'check' when files.isEmpty:
      final all = _all(dir);
      if (all.isEmpty) {
        out.writeln('no fixtures in $dir (run this in packages/trip_engine)');
        return 1;
      }
      return _check(all, out);
    case 'check':
      return _check(files, out);
    case 'update' when files.isNotEmpty:
      return _update(files, out);
    case 'show' when files.length == 1:
      return _show(files.single, out);
    default:
      err.writeln(_usage);
      return 64;
  }
}

// The fixture files in [dir], or none when it doesn't exist.
List<String> _all(String dir) {
  final directory = Directory(dir);
  if (!directory.existsSync()) return const [];
  return [
    for (final entity in directory.listSync())
      if (entity is File && entity.path.endsWith('.json')) entity.path,
  ]..sort();
}

Object? _read(String path) => jsonDecode(File(path).readAsStringSync());

int _check(List<String> files, StringSink out) {
  var failed = 0;
  for (final path in files) {
    final problems = _problems(path);
    if (problems.isEmpty) continue;
    failed++;
    for (final problem in problems) {
      out.writeln('$path: $problem');
    }
  }
  out.writeln('${files.length} fixtures checked, $failed differ');
  return failed == 0 ? 0 : 1;
}

List<String> _problems(String path) {
  try {
    final text = File(path).readAsStringSync();
    final fixture = ParityFixture.fromJson(jsonDecode(text));
    return [
      ...fixture.differences(),
      if (fixture.encode() != text) 'not in the canonical layout (run update)',
    ];
  } on FormatException catch (error) {
    return ['malformed: ${error.message}'];
  } on RebuildRefused catch (error) {
    return ['$error'];
  } on FileSystemException catch (error) {
    return ['unreadable: ${error.message}'];
  }
}

int _update(List<String> files, StringSink out) {
  var failed = 0;
  for (final path in files) {
    try {
      final file = File(path);
      final before = file.readAsStringSync();
      final after = ParityFixture.recomputed(jsonDecode(before)).encode();
      file.writeAsStringSync(after);
      out.writeln('${before == after ? 'unchanged' : 'updated'} $path');
    } on FormatException catch (error) {
      failed++;
      out.writeln('$path: malformed: ${error.message}');
    } on RebuildRefused catch (error) {
      failed++;
      out.writeln('$path: $error');
    } on FileSystemException catch (error) {
      failed++;
      out.writeln('$path: unreadable: ${error.message}');
    }
  }
  return failed == 0 ? 0 : 1;
}

int _show(String path, StringSink out) {
  try {
    final fixture = ParityFixture.recomputed(_read(path));
    final engine = replayEngine(
      fixture.definition,
      fixture.params,
      fixture.seed,
      fixture.commandLog,
      onEvents: (events) {
        for (final event in events) {
          out.writeln(
            '${event.name} ${event.tMs} ${jsonEncode(event.payload)}',
          );
        }
      },
    );
    out.writeln('result ${jsonEncode(engine.result?.toJson())}');
    return 0;
  } on FormatException catch (error) {
    out.writeln('$path: malformed: ${error.message}');
  } on RebuildRefused catch (error) {
    out.writeln('$path: $error');
  } on FileSystemException catch (error) {
    out.writeln('$path: unreadable: ${error.message}');
  }
  return 1;
}
