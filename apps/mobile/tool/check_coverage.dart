// The coverage gate for CI (contracts/ci-checks.md «Coverage rules»).
//
// Usage:
//   dart run tool/check_coverage.dart --min 80 [--lcov coverage/lcov.info] [--lib lib]
//
// Exits 1 when line coverage is below --min, and 2 on bad arguments. Every
// lib/ file that no test loads counts as 0% covered, so it cannot hide.
// No dependencies, so CI runs it straight after `flutter test --coverage`.
import 'dart:io';

/// Coverage of one lib/ file.
final class FileCoverage {
  const FileCoverage(
    this.path, {
    required this.hit,
    required this.found,
    this.missed = const [],
    this.loaded = true,
  });

  /// Relative to the package root, for example `lib/main.dart`.
  final String path;
  final int hit;
  final int found;

  /// Executable lines no test ran.
  final List<int> missed;

  /// False when no test loaded the file, so [found] is an estimate.
  final bool loaded;
}

final class CoverageReport {
  const CoverageReport(this.files);

  final List<FileCoverage> files;

  int get hit => files.fold(0, (sum, f) => sum + f.hit);
  int get found => files.fold(0, (sum, f) => sum + f.found);
  double get percent => found == 0 ? 100 : hit * 100 / found;
}

bool _excluded(String path) =>
    path.endsWith('.g.dart') ||
    path.startsWith('lib/l10n/generated/') ||
    path == 'lib/main.dart';

CoverageReport computeCoverage({
  required String lcov,
  required Directory libDir,
}) {
  final reported = <String, FileCoverage>{};
  String? path;
  var lines = <int, int>{};
  for (final line in lcov.split('\n').map((l) => l.trim())) {
    if (line.startsWith('SF:')) {
      path = _libRelative(line.substring(3));
      lines = {};
    } else if (line.startsWith('DA:')) {
      final [number, count, ...] = line.substring(3).split(',');
      lines[int.parse(number)] = int.parse(count);
    } else if (line == 'end_of_record' && path != null) {
      final missed = [
        for (final MapEntry(:key, :value) in lines.entries)
          if (value == 0) key,
      ]..sort();
      reported[path] = FileCoverage(
        path,
        hit: lines.length - missed.length,
        found: lines.length,
        missed: missed,
      );
      path = null;
    }
  }

  final files = <FileCoverage>[];
  for (final file in libDir.listSync(recursive: true).whereType<File>()) {
    if (!file.path.endsWith('.dart')) continue;
    final relative = file.path
        .substring(libDir.path.length)
        .replaceAll(r'\', '/')
        .replaceFirst(RegExp('^/'), '');
    final key = 'lib/$relative';
    if (_excluded(key)) continue;
    final coverage = reported[key] ?? _unreported(key, file.readAsStringSync());
    if (coverage != null) files.add(coverage);
  }
  files.sort((a, b) => a.path.compareTo(b.path));
  return CoverageReport(files);
}

/// Maps an lcov `SF:` path to `lib/…`, or null for files outside lib/.
String? _libRelative(String sourceFile) {
  var path = sourceFile.replaceAll(r'\', '/');
  final root = '${Directory.current.path.replaceAll(r'\', '/')}/';
  if (path.startsWith(root)) path = path.substring(root.length);
  return path.startsWith('lib/') ? path : null;
}

/// A file missing from lcov. The Dart VM leaves out files with no code to
/// run (constants, abstract interfaces), so only a file with a function
/// body is a file no test loaded.
FileCoverage? _unreported(String path, String source) {
  final code = source
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('//'))
      .join('\n');
  if (!_functionBody.hasMatch(code)) return null;
  return FileCoverage(
    path,
    hit: 0,
    found: _estimateExecutableLines(source),
    loaded: false,
  );
}

final _functionBody = RegExp(r'\)\s*(async\*?|sync\*)?\s*\{|=>');

final _notExecutable = RegExp(
  r'^(//|/\*|\*|import |export |part |library\b|[\[\](){};,]+$)',
);

/// Lines a test would have to run in a file no test loaded: everything
/// except blanks, comments, directives and lone brackets.
int _estimateExecutableLines(String source) => source
    .split('\n')
    .map((l) => l.trim())
    .where((l) => l.isNotEmpty && !_notExecutable.hasMatch(l))
    .length;

const _usage =
    'Usage: dart run tool/check_coverage.dart --min <percent> '
    '[--lcov coverage/lcov.info] [--lib lib]';

/// Runs the gate and returns the exit code.
Future<int> runGate(List<String> args, {required StringSink out}) async {
  double? min;
  var lcovPath = 'coverage/lcov.info';
  var libPath = 'lib';
  for (var i = 0; i < args.length; i++) {
    final value = i + 1 < args.length ? args[i + 1] : null;
    switch (args[i]) {
      case '--min' when value != null:
        min = double.tryParse(value);
      case '--lcov' when value != null:
        lcovPath = value;
      case '--lib' when value != null:
        libPath = value;
      default:
        out.writeln(_usage);
        return 2;
    }
    i++;
  }
  final lcovFile = File(lcovPath);
  if (min == null || !lcovFile.existsSync()) {
    out.writeln(min == null ? _usage : 'No coverage file at $lcovPath.');
    return 2;
  }

  final report = computeCoverage(
    lcov: lcovFile.readAsStringSync(),
    libDir: Directory(libPath),
  );
  final incomplete = report.files.where((f) => f.hit < f.found).toList()
    ..sort((a, b) => (b.found - b.hit).compareTo(a.found - a.hit));
  for (final f in incomplete) {
    final pct = (f.hit * 100 / f.found).toStringAsFixed(1).padLeft(5);
    final detail = f.loaded
        ? 'missed lines ${f.missed.join(', ')}'
        : 'not loaded by any test';
    out.writeln('$pct%  ${f.path}  (${f.hit}/${f.found}; $detail)');
  }
  final total = report.percent;
  out.writeln(
    'Total: ${total.toStringAsFixed(2)}% '
    '(${report.hit}/${report.found} lines), minimum $min%.',
  );
  return total < min ? 1 : 0;
}

Future<void> main(List<String> args) async {
  exitCode = await runGate(args, out: stdout);
}
