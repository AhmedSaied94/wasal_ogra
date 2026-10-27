import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// The game database stays out of Android's device backup and phone-to-phone
// transfer (specs/007-m05-local-economy FR-006, research R14), and so do
// the session's tokens (specs/011-m06-identity-sync FR-005, research R2).
// The rules stay exclude-only: an <include> would limit the backup to the
// files it lists, and drop the install id's own file, which the backup
// carries across a re-install (research R1).

const _res = 'android/app/src/main/res/xml';
const _exclude = '<exclude domain="file" path="db/"/>';

/// The files flutter_secure_storage 11.2.0 writes with no
/// `storageNamespace` (research R2). A plugin upgrade must check the names
/// again.
const _secureStorageFiles = [
  'FlutterSecureStorage.xml',
  'FlutterSecureKeyStorage.xml',
  'FlutterSecureStorageConfiguration.xml',
  'FlutterSecureStorageConfiguration:FlutterSecureStorage.xml',
];

String _excludePref(String file) =>
    '<exclude domain="sharedpref" path="$file"/>';

/// The install id's file, which the default backup carries.
const _installFile = 'wassal_install.xml';

/// What a backup section must hold, and must not.
void _checkSection(String section, String name) {
  expect(section, contains(_exclude), reason: name);
  for (final file in _secureStorageFiles) {
    expect(section, contains(_excludePref(file)), reason: '$name: $file');
  }
  expect(section, isNot(contains(_installFile)), reason: name);
}

/// The XML of each [section] element in [xml].
List<String> sections(String xml, String section) => [
  for (final match in RegExp(
    '<$section>(.*?)</$section>',
    dotAll: true,
  ).allMatches(xml))
    match[1]!,
];

void main() {
  test('the manifest names both rule files on <application>', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    final application = RegExp(
      '<application[^>]*>',
      dotAll: true,
    ).firstMatch(manifest)![0]!;
    expect(
      application,
      contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
    );
    expect(
      application,
      contains('android:fullBackupContent="@xml/backup_rules"'),
    );
  });

  test('Android 12+ excludes db/ and the secure store from cloud backup '
      'and device transfer', () {
    final xml = File('$_res/data_extraction_rules.xml').readAsStringSync();
    for (final section in ['cloud-backup', 'device-transfer']) {
      final found = sections(xml, section);
      expect(found, hasLength(1), reason: section);
      _checkSection(found.single, section);
    }
  });

  test('Android 11 and earlier exclude db/ and the secure store from full '
      'backup', () {
    final xml = File('$_res/backup_rules.xml').readAsStringSync();
    final found = sections(xml, 'full-backup-content');
    expect(found, hasLength(1));
    _checkSection(found.single, 'full-backup-content');
  });

  test('neither file has an <include>, so the rest keeps its backup', () {
    for (final file in ['data_extraction_rules.xml', 'backup_rules.xml']) {
      final xml = File('$_res/$file').readAsStringSync();
      expect(xml, isNot(contains('<include')), reason: file);
    }
  });

  test('the section scan finds what it should', () {
    const xml = '<a><cloud-backup>$_exclude</cloud-backup><b/></a>';
    expect(sections(xml, 'cloud-backup'), [_exclude]);
    expect(sections(xml, 'device-transfer'), isEmpty);
  });
}
