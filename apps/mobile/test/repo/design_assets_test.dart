import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/design/sync_assets.dart';

// The design's icons and illustrations in the app equal docs/design
// (specs/008.5-m21-design-refresh, research R19). Fix a failure with
// `fvm dart run tool/design/sync_assets.dart`.

final _design = Directory('../../docs/design');
final _assets = Directory('assets');

/// Every difference between [design] and [assets], one line each.
List<String> _drift(Directory design, Directory assets) {
  final problems = <String>[];
  final listed = <String>{};
  for (final f in syncedFiles(design)) {
    listed.add(f.target);
    final source = File('${design.path}/${f.source}');
    final copy = File('${assets.path}/${f.target}');
    if (!source.existsSync()) {
      problems.add('docs/design/${f.source}: missing in the design');
    } else if (!copy.existsSync()) {
      problems.add('assets/${f.target}: not copied');
    } else if (!_sameBytes(source, copy)) {
      problems.add('assets/${f.target}: differs from docs/design/${f.source}');
    }
  }
  for (final folder in ['icons', 'illustrations']) {
    final dir = Directory('${assets.path}/$folder');
    if (!dir.existsSync()) continue;
    for (final file in dir.listSync(recursive: true).whereType<File>()) {
      final path = file.path
          .replaceAll(r'\', '/')
          .substring(assets.path.length + 1);
      if (!listed.contains(path)) {
        problems.add('assets/$path: not in sync_assets.dart');
      }
    }
  }
  return problems;
}

bool _sameBytes(File a, File b) {
  final x = a.readAsBytesSync();
  final y = b.readAsBytesSync();
  if (x.length != y.length) return false;
  for (var i = 0; i < x.length; i++) {
    if (x[i] != y[i]) return false;
  }
  return true;
}

void main() {
  test("the app's design assets equal docs/design", () {
    final problems = _drift(_design, _assets);
    expect(
      problems,
      isEmpty,
      reason:
          '${problems.join('\n')}\n'
          'Run: fvm dart run tool/design/sync_assets.dart',
    );
  });

  test('every icon is synced', () {
    final count = syncedFiles(_design)
        .where((f) => f.target.startsWith('icons/'))
        .length;
    expect(count, 92);
  });

  group('the check catches', () {
    late Directory temp;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('design_assets');
      addTearDown(() => temp.deleteSync(recursive: true));
      syncAssets(design: _design, assets: temp);
    });

    test('a copy with one changed byte, by its path', () {
      final file = File('${temp.path}/icons/fuel.svg');
      final bytes = file.readAsBytesSync();
      bytes[bytes.length ~/ 2] ^= 1;
      file.writeAsBytesSync(bytes);
      expect(_drift(_design, temp), [
        'assets/icons/fuel.svg: differs from docs/design/icons/fuel.svg',
      ]);
    });

    test('a file nobody lists', () {
      File('${temp.path}/icons/stray.svg').writeAsStringSync('<svg/>');
      expect(_drift(_design, temp), [
        'assets/icons/stray.svg: not in sync_assets.dart',
      ]);
    });

    test('a missing copy', () {
      File('${temp.path}/illustrations/characters/belya.svg').deleteSync();
      expect(_drift(_design, temp), [
        'assets/illustrations/characters/belya.svg: not copied',
      ]);
    });
  });

  test('a missing design file stops the sync before it copies anything', () {
    final design = Directory.systemTemp.createTempSync('design_src');
    final assets = Directory.systemTemp.createTempSync('design_dst');
    addTearDown(() {
      design.deleteSync(recursive: true);
      assets.deleteSync(recursive: true);
    });
    Directory('${design.path}/icons').createSync();
    expect(
      () => syncAssets(design: design, assets: assets),
      throwsA(
        isA<FileSystemException>().having(
          (e) => e.path,
          'path',
          endsWith('illustrations/passengers/regular.svg'),
        ),
      ),
    );
    expect(assets.listSync(), isEmpty);
  });
}
