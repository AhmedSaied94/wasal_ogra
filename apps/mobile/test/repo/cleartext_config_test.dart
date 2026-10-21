import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Plain HTTP only from the dev flavor to the developer's own machine
// (constitution 1.2.0, Security & privacy; specs/006-m04-content-loader/
// research.md R12). Staging and prod builds merge main, their flavor's
// source set and the debug or profile one, so none of those may open it.

const _src = 'android/app/src';
const _devConfig = '$_src/dev/res/xml/network_security_config.xml';
const _devHosts = {'localhost', '127.0.0.1', '10.0.2.2'};

Iterable<Directory> _sourceSets() =>
    Directory(_src).listSync().whereType<Directory>();

String _name(FileSystemEntity entity) =>
    entity.uri.pathSegments.lastWhere((segment) => segment.isNotEmpty);

void main() {
  test('only the dev source set has a network security config', () {
    final configs = [
      for (final set in _sourceSets())
        if (File('${set.path}/res/xml/network_security_config.xml')
            .existsSync())
          _name(set),
    ];
    expect(configs, ['dev']);
  });

  test('the dev config allows cleartext to the dev machine only', () {
    final xml = File(_devConfig).readAsStringSync();
    expect(
      RegExp('<base-config[^>]*cleartextTrafficPermitted="true"').hasMatch(xml),
      isFalse,
    );
    final configs = RegExp(
      r'<domain-config([^>]*)>(.*?)</domain-config>',
      dotAll: true,
    ).allMatches(xml).toList();
    expect(configs, hasLength(1));
    expect(configs.single[1], contains('cleartextTrafficPermitted="true"'));
    final domains = {
      for (final match in RegExp(
        r'<domain[^>]*>\s*([^<\s]+)\s*</domain>',
      ).allMatches(configs.single[2]!))
        match[1]!,
    };
    expect(domains, _devHosts);
    expect(
      RegExp(r'includeSubdomains="true"').hasMatch(xml),
      isFalse,
      reason: 'no subdomain of a dev host',
    );
  });

  test('the dev manifest points at the config', () {
    final manifest = File('$_src/dev/AndroidManifest.xml').readAsStringSync();
    expect(
      manifest,
      contains('android:networkSecurityConfig="@xml/network_security_config"'),
    );
  });

  test('no other manifest opens cleartext', () {
    for (final set in _sourceSets()) {
      if (_name(set) == 'dev') continue;
      final file = File('${set.path}/AndroidManifest.xml');
      if (!file.existsSync()) continue;
      final manifest = file.readAsStringSync();
      expect(
        manifest,
        isNot(contains('networkSecurityConfig')),
        reason: file.path,
      );
      expect(
        manifest,
        isNot(contains('usesCleartextTraffic')),
        reason: file.path,
      );
    }
  });

  test('main declares the INTERNET permission', () {
    expect(
      File('$_src/main/AndroidManifest.xml').readAsStringSync(),
      contains('<uses-permission android:name="android.permission.INTERNET"/>'),
    );
  });
}
