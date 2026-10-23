// The owner's Rive file matches its contract (tasks.md T100,
// contracts/rive-characters.md "The file", "Tests"). Needs Rive's Linux
// library: `fvm dart run rive_native:setup --verbose --clean --platform linux`.
@Tags(['rive'])
library;

import 'dart:io' as io;
import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:rive/rive.dart';
import 'package:wassal/core/art/rive_art.dart';

/// About 3 MB (contracts/rive-characters.md "Export").
const _maxBytes = 3 * 1024 * 1024;

void main() {
  late File file;

  setUpAll(() async {
    await RiveNative.init();
    final bytes = io.File(riveArtAsset).readAsBytesSync();
    expect(bytes.length, lessThan(_maxBytes));
    file = (await File.decode(bytes, riveFactory: Factory.flutter))!;
  });

  tearDownAll(() => file.dispose());

  for (final MapEntry(key: name, value: spec) in riveContract.entries) {
    test('$name: its size, state machine and view model', () {
      final artboard = file.artboard(name);
      expect(artboard, isNotNull, reason: 'artboard $name');
      addTearDown(artboard!.dispose);
      expect(
        Size(artboard.width, artboard.height),
        spec.size,
        reason: '$name size',
      );
      final machine = artboard.stateMachine(spec.machine);
      expect(machine, isNotNull, reason: 'state machine ${spec.machine}');
      machine!.dispose();

      final model = file.defaultArtboardViewModel(artboard);
      addTearDown(() => model?.dispose());
      if (spec.viewModel == null) return;
      expect(model?.name, spec.viewModel, reason: '$name default view model');
      final types = {for (final p in model!.properties) p.name: p.type};
      for (final MapEntry(key: property, value: type)
          in spec.properties.entries) {
        expect(types[property], type, reason: '${spec.viewModel}.$property');
      }
    });
  }

  test('the check passes every artboard, and finds no problem', () {
    final art = checkRiveArt(file);
    expect(art.usable, riveContract.keys.toSet());
    expect(art.problems, isEmpty);
  });

  test("the free export's own artboards are known, and nothing else", () {
    // contracts/rive-characters.md "Export": the owner exports from the
    // free plan, whose splash comes as artboards the app never draws.
    expect(riveExportArtboards, {
      'iPhone 16 - 1',
      'Watermark',
      'NuRiveBrandmark01',
      'NuRiveWordmark01',
    });
    expect(
      riveExportArtboards.intersection(riveContract.keys.toSet()),
      isEmpty,
    );
  });

  testWidgets('loads from the bundle, as boot does', (tester) async {
    final art = await tester.runAsync(loadRiveArt);
    addTearDown(() => art?.file?.dispose());
    expect(art!.file, isNotNull, reason: '${art.problems}');
    expect(art.has('Person'), isTrue);
  });

  testWidgets('a check that throws: the static art, never a failed boot', (
    tester,
  ) async {
    final art = await tester.runAsync(
      () => loadRiveArt(check: (_) => throw StateError('broken')),
    );
    expect(art!.file, isNull);
    expect(art.problems, [contains('broken')]);
  });
}
