// Copies the design's icons and illustrations into the app's assets
// (specs/008.5-m21-design-refresh, research R19). Flutter bundles only files
// under the package, so the SVGs are copied byte for byte, and
// test/repo/design_assets_test.dart keeps the copies equal to docs/design.
//
// Usage, from apps/mobile:
//   fvm dart run tool/design/sync_assets.dart
//
// Exits 1 when a source file is missing, naming it. Deletes nothing.
import 'dart:io';

/// Each asset folder, the design folder it comes from, and the files it
/// takes. `files: null` takes every SVG in the design folder.
const syncedFolders = <String, ({String from, List<String>? files})>{
  'icons': (from: 'icons', files: null),
  'illustrations/passengers': (
    from: 'illustrations/passengers',
    files: [
      'regular.svg',
      'hagga.svg',
      'sleeper.svg',
      'hurried.svg',
      'effendi_200.svg',
      'student.svg',
      'headphones.svg',
      'claimer.svg',
      'group_payer.svg',
      'chatterbox.svg',
      'regular_customer.svg',
      'honest.svg',
    ],
  ),
  'illustrations/characters': (
    from: 'illustrations/characters',
    files: [
      'usta.svg',
      'salma.svg',
      'bride_father.svg',
      'bride_mother.svg',
      'moallem.svg',
      'belya.svg',
    ],
  ),
  'illustrations/vehicles': (
    from: 'illustrations/vehicles',
    // Every vehicle has its own static fallback, the two later microbuses
    // included (specs/014-m09-lines-vehicles, research R10).
    files: [
      'tuktuk.svg',
      'microbus_old.svg',
      'microbus_new.svg',
      'microbus_travel.svg',
    ],
  ),
  'illustrations/screens': (
    from: 'illustrations/screens',
    files: ['Loading_01.svg'],
  ),
};

/// Files copied under another name: the scenes' panel drawings, named by the
/// panel's `art` slug (specs/012-m07-onboarding/contracts/scenes.md "Panel
/// art"). Each is a (source in `docs/design`, target in `assets`) pair.
const renamedFiles = <SyncedFile>[
  (
    source: 'illustrations/screens/Intro_01.svg',
    target: 'illustrations/panels/opening_key.svg',
  ),
  (
    source: 'illustrations/screens/PanelOpeningStand_01.svg',
    target: 'illustrations/panels/opening_stand.svg',
  ),
  (
    source: 'illustrations/screens/PanelOpeningGo_01.svg',
    target: 'illustrations/panels/opening_go.svg',
  ),
  (
    source: 'illustrations/screens/PanelStandMorning_01.svg',
    target: 'illustrations/panels/stand_morning.svg',
  ),
  (
    source: 'illustrations/screens/PanelSalmaWaiting_01.svg',
    target: 'illustrations/panels/salma_waiting.svg',
  ),
  (
    source: 'illustrations/screens/PanelUstaDecides_01.svg',
    target: 'illustrations/panels/usta_decides.svg',
  ),
];

/// One file to copy, as paths relative to `docs/design` and `assets`.
typedef SyncedFile = ({String source, String target});

/// Every file [syncedFolders] names, with `files: null` expanded from
/// [design], then [renamedFiles]. Sorted, so the order never depends on the
/// file system.
List<SyncedFile> syncedFiles(Directory design) {
  final out = <SyncedFile>[];
  for (final MapEntry(key: target, value: folder) in syncedFolders.entries) {
    final names =
        folder.files ??
        (Directory('${design.path}/${folder.from}')
            .listSync()
            .whereType<File>()
            .map((f) => f.uri.pathSegments.last)
            .where((name) => name.endsWith('.svg'))
            .toList()
          ..sort());
    for (final name in names) {
      out.add((source: '${folder.from}/$name', target: '$target/$name'));
    }
  }
  return out..addAll(renamedFiles);
}

/// Copies every synced file from [design] to [assets]. Throws a
/// [FileSystemException] naming the first missing source, before copying
/// anything.
int syncAssets({required Directory design, required Directory assets}) {
  final files = syncedFiles(design);
  for (final f in files) {
    final source = File('${design.path}/${f.source}');
    if (!source.existsSync()) {
      throw FileSystemException('missing design file', source.path);
    }
  }
  for (final f in files) {
    final target = File('${assets.path}/${f.target}');
    target.parent.createSync(recursive: true);
    target.writeAsBytesSync(
      File('${design.path}/${f.source}').readAsBytesSync(),
    );
  }
  return files.length;
}

void main() {
  final script = File.fromUri(Platform.script);
  final mobile = script.parent.parent.parent;
  final design = Directory('${mobile.path}/../../docs/design');
  try {
    final count = syncAssets(
      design: design,
      assets: Directory('${mobile.path}/assets'),
    );
    stdout.writeln('Copied $count files from ${design.path}.');
  } on FileSystemException catch (e) {
    stderr.writeln('${e.message}: ${e.path}');
    exitCode = 1;
  }
}
