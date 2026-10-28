// The tutorial content for M07's tests (specs/012-m07-onboarding/research.md
// R20): the release draft's five tutorial trips, copied into
// test/fixtures/tutorial/, layered over the bundled sample. The sample's own
// trips stay as they are.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:content_models/content_models.dart';
import 'package:wassal/core/content/decode_pack_file.dart';
import 'package:wassal/core/content/domain/content_source.dart';

import 'content.dart';

const _fixture = 'test/fixtures/tutorial';

/// The tutorial line's wire name.
const tutorialLineId = 'line_hay';

/// The fixture's tutorial trips, in order.
const tutorialTripIds = [
  'line_hay.01',
  'line_hay.02',
  'line_hay.03',
  'line_hay.04',
  'line_hay.05',
];

Map<String, Object?> _json(String path) =>
    (jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>)
        .cast<String, Object?>();

List<Map<String, Object?>> _list(Object? value) => [
  for (final item in value! as List<Object?>)
    (item! as Map<String, dynamic>).cast<String, Object?>(),
];

/// The sample pack's JSON with the fixture in place of its `line_hay`:
/// - the draft's `line_hay` definition;
/// - the draft's trips 01–05 instead of the sample's `line_hay` trips;
/// - the sleeper's speech pools added (keyed by their file names, as the
///   content kit does).
Map<String, Object?> tutorialPackJson() {
  final sample = samplePackJson();
  final line = _json('$_fixture/lines/line_hay.json');
  final trips = [
    for (final id in tutorialTripIds)
      _json('$_fixture/trips/line_hay/$id.json'),
  ];
  final pools = [
    for (final file
        in Directory('$_fixture/speech').listSync().whereType<File>().toList()
          ..sort((a, b) => a.path.compareTo(b.path)))
      {
        ..._json(file.path),
        'speech_key': file.uri.pathSegments.last.replaceAll('.json', ''),
      },
  ];
  final poolKeys = {for (final p in pools) p['speech_key']};
  return {
    ...sample,
    'lines': [
      for (final l in _list(sample['lines']))
        if (l['line_id'] == tutorialLineId) line else l,
    ],
    'trips': [
      for (final t in _list(sample['trips']))
        if (t['line_id'] != tutorialLineId) t,
      ...trips,
    ],
    'speech_pools': [
      for (final p in _list(sample['speech_pools']))
        if (!poolKeys.contains(p['speech_key'])) p,
      ...pools,
    ],
  };
}

/// [tutorialPackJson] as a pack file, as the bundle would hold it.
EncodedPack tutorialPackFile() => encodePackFile(tutorialPackJson());

ContentSource? _tutorial;

/// The tutorial content: the sample with the fixture's `line_hay` and its
/// five trips. Decoded once, through the app's own decoder.
ContentSource tutorialContent() => _tutorial ??= _decode(tutorialPackFile());

ContentSource _decode(EncodedPack pack) {
  final result = decodePackFile(pack.bytes, pack.expected);
  return switch (result) {
    PackDecoded(:final source) => source,
    PackRefused(:final reason) => throw StateError(
      'the tutorial fixture is refused: $reason',
    ),
  };
}

/// Dev bundled assets holding [tutorialPackFile] instead of the sample.
Map<String, Uint8List?> tutorialBundledAssets() =>
    bundledAssetsFor(tutorialPackFile());

/// [tutorialBundledAssets] bundled for every flavor: staging and prod read
/// `assets/content/release/`.
Map<String, Uint8List?> tutorialBundledAssetsAllFlavors() {
  final dev = tutorialBundledAssets();
  return {
    ...dev,
    for (final MapEntry(:key, :value) in dev.entries)
      key.replaceFirst('/dev/', '/release/'): value,
  };
}

/// A fixture trip's definition.
TripDefinition tutorialTrip(String tripId) => tutorialContent().trip(tripId)!;

/// The draft's سلمى scene, `first_sight`, under its `ch1_*` panel names
/// (specs/012.5-m22-animated-scenes, research R11).
Scene draftFirstSight() => Scene.fromJson(_json('$_fixture/first_sight.json'));

/// The sample with no scene that plays by itself: every `plays` removed,
/// so the pack has no opening scene (FR-010).
Map<String, Object?> sampleWithoutSessionScenesJson() {
  final sample = samplePackJson();
  return {
    ...sample,
    'chapters': [
      for (final chapter in _list(sample['chapters']))
        {
          ...chapter,
          'scenes': [
            for (final scene in _list(chapter['scenes']))
              {
                for (final MapEntry(:key, :value) in scene.entries)
                  if (key != 'plays') key: value,
              },
          ],
        },
    ],
  };
}

/// Dev bundled assets holding [sampleWithoutSessionScenesJson].
Map<String, Uint8List?> noSessionScenesAssets() =>
    bundledAssetsFor(encodePackFile(sampleWithoutSessionScenesJson()));
