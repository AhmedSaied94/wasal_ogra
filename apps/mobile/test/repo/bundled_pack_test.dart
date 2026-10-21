import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/content/client_version.dart';

// What refuses a wrong build (specs/006-m04-content-loader/contracts/
// bundling.md): every bundled record agrees with its file, the dev pack is
// the sample's golden build, and the app's version meets every pack it ships.

Map<String, dynamic> _json(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

/// The `bundled.json` of every asset directory that has one.
List<Directory> _bundledDirs() => [
  for (final dir in Directory(
    'assets/content',
  ).listSync().whereType<Directory>())
    if (File('${dir.path}/bundled.json').existsSync()) dir,
];

String _pubspecVersion() => RegExp(
  r'^version:\s*(\S+)\s*$',
  multiLine: true,
).firstMatch(File('pubspec.yaml').readAsStringSync())![1]!;

void main() {
  test('every bundled record agrees with its file', () {
    final dirs = _bundledDirs();
    expect(dirs.map((d) => d.path), contains('assets/content/dev'));
    for (final dir in dirs) {
      final record = _json('${dir.path}/bundled.json');
      final file = File('${dir.path}/${record['file']}');
      expect(file.existsSync(), isTrue, reason: file.path);
      final bytes = file.readAsBytesSync();
      expect(bytes.length, record['size'], reason: file.path);
      expect(sha256.convert(bytes).toString(), record['sha256']);
      expect(record['file'], 'core-${record['version']}.json.gz');
    }
  });

  test("the dev pack is the sample's golden build", () {
    final record = _json('assets/content/dev/bundled.json');
    final golden = _json('../../content/examples/sample.golden.json');
    expect(record['sha256'], golden['sha256']);
    expect(record['size'], golden['size']);
    expect(record['version'], golden['version']);
    expect(record['source'], 'sample');
  });

  test('the app version is MAJOR.MINOR.PATCH+BUILD', () {
    expect(_pubspecVersion(), matches(RegExp(r'^\d+\.\d+\.\d+\+\d+$')));
  });

  test('the app version meets the schema floor and every bundled pack', () {
    final app = ClientVersion.parse(_pubspecVersion())!;
    final floors =
        _json(
              '../../content/schemas/schema-set.json',
            )['min_client_version_by_major']
            as Map<String, dynamic>;
    final floor = ClientVersion.parse(floors['1'] as String)!;
    expect(
      app.atLeast(floor),
      isTrue,
      reason: '$app is below the floor $floor',
    );
    for (final dir in _bundledDirs()) {
      final record = _json('${dir.path}/bundled.json');
      final minimum = ClientVersion.parse(
        record['min_client_version'] as String,
      )!;
      expect(app.atLeast(minimum), isTrue, reason: '${dir.path}: $minimum');
    }
  });

  group('the release directory', () {
    const release = 'assets/content/release';
    final packJson = File('../../content/source/pack.json');
    final version = packJson.existsSync()
        ? _json(packJson.path)['version'] as int
        : 0;

    test('holds the promoted pack, or only README.md before one', () {
      final names = {
        for (final entity in Directory(release).listSync())
          entity.uri.pathSegments.lastWhere((s) => s.isNotEmpty),
      };
      expect(
        names,
        version > 0
            ? {
                'bundled.json',
                'core-$version.json.gz',
                'core-$version.release.json',
              }
            : {'README.md'},
      );
    });

    test("agrees with production's release record", () {
      final record = _json('$release/bundled.json');
      expect(record['version'], version);
      expect(record['source'], 'content_source');
      final copy = File('$release/core-$version.release.json');
      final releaseRecord =
          jsonDecode(copy.readAsStringSync()) as Map<String, dynamic>;
      expect(releaseRecord['sha256'], record['sha256']);
      expect(releaseRecord['size'], record['size']);
      expect(
        record['release_record_sha256'],
        sha256.convert(copy.readAsBytesSync()).toString(),
      );
      final minimum = ClientVersion.parse(
        record['min_client_version'] as String,
      )!;
      expect(ClientVersion.parse(_pubspecVersion())!.atLeast(minimum), isTrue);
    }, skip: version > 0 ? false : 'production has promoted no pack yet');
  });
}
