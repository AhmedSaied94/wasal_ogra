import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// The game database stays out of Android's device backup and phone-to-phone
// transfer (specs/007-m05-local-economy FR-006, research R14).

const _res = 'android/app/src/main/res/xml';
const _exclude = '<exclude domain="file" path="db/"/>';

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

  test('Android 12+ excludes db/ from cloud backup and device transfer', () {
    final xml = File('$_res/data_extraction_rules.xml').readAsStringSync();
    for (final section in ['cloud-backup', 'device-transfer']) {
      final found = sections(xml, section);
      expect(found, hasLength(1), reason: section);
      expect(found.single, contains(_exclude), reason: section);
    }
  });

  test('Android 11 and earlier exclude db/ from full backup', () {
    final xml = File('$_res/backup_rules.xml').readAsStringSync();
    final found = sections(xml, 'full-backup-content');
    expect(found, hasLength(1));
    expect(found.single, contains(_exclude));
  });

  test('the section scan finds what it should', () {
    const xml = '<a><cloud-backup>$_exclude</cloud-backup><b/></a>';
    expect(sections(xml, 'cloud-backup'), [_exclude]);
    expect(sections(xml, 'device-transfer'), isEmpty);
  });
}
