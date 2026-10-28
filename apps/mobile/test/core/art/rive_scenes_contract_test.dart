// The scenes' Rive file matches its contract (specs/012.5-m22-animated-scenes,
// contracts/rive-scenes.md, contracts/ci-checks.md "Rive tests"). Needs Rive's
// Linux library: `fvm dart run rive_native:setup --verbose --clean --platform
// linux`.
@Tags(['rive'])
library;

import 'dart:io' as io;
import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:rive/rive.dart';
import 'package:wassal/core/art/rive_art.dart';
import 'package:wassal/core/art/rive_scenes.dart';

/// The file's budget (spec SC-006).
const _maxBytes = 100 * 1024;

const _prefix = 'assets/rive/wassal_scenes.riv: ';

/// [sceneContract] with [slug]'s spec changed by [change].
RiveContract _changed(
  String slug,
  ArtboardSpec Function(ArtboardSpec spec) change,
) => RiveContract(
  asset: sceneContract.asset,
  artboards: {
    for (final MapEntry(:key, :value) in sceneContract.artboards.entries)
      key: key == slug ? change(value) : value,
  },
  known: sceneContract.known,
);

ArtboardSpec _spec(
  ArtboardSpec spec, {
  Size? size,
  String? machine,
  String? viewModel,
  Map<String, DataType>? properties,
}) => (
  size: size ?? spec.size,
  machine: machine ?? spec.machine,
  viewModel: viewModel ?? spec.viewModel,
  properties: properties ?? spec.properties,
);

final _others = {...scenePanelSlugs}..remove('opening_key');

void main() {
  late File file;

  setUpAll(() async {
    await RiveNative.init();
    final bytes = io.File(riveScenesAsset).readAsBytesSync();
    expect(bytes.length, lessThan(_maxBytes));
    file = (await File.decode(bytes, riveFactory: Factory.flutter))!;
  });

  tearDownAll(() => file.dispose());

  for (final MapEntry(key: name, value: spec)
      in sceneContract.artboards.entries) {
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
      expect(model?.name, spec.viewModel, reason: '$name default view model');
      final types = {for (final p in model!.properties) p.name: p.type};
      for (final MapEntry(key: property, value: type)
          in spec.properties.entries) {
        expect(types[property], type, reason: '${spec.viewModel}.$property');
      }
    });
  }

  test('the file holds the panels and the known artboards, and nothing '
      'else', () {
    final names = <String>{};
    for (var i = 0; ; i++) {
      final artboard = file.artboardAt(i);
      if (artboard == null) break;
      names.add(artboard.name);
      artboard.dispose();
    }
    expect(names, {...sceneContract.artboards.keys, ...sceneContract.known});
  });

  test('the check passes every panel, and finds no problem', () {
    final art = checkRiveArt(file, sceneContract);
    expect(art.usable, sceneContract.artboards.keys.toSet());
    expect(art.problems, isEmpty);
    expect(art.contract, same(sceneContract));
  });

  group('one change to the contract: that panel alone is its drawing, '
      'with the contract\'s problem text', () {
    final cases = <String, (RiveContract, String)>{
      'a wrong size': (
        _changed('opening_key', (s) => _spec(s, size: const Size(360, 540))),
        'artboard opening_key: 358×540, not 360×540',
      ),
      'another machine name': (
        _changed('opening_key', (s) => _spec(s, machine: 'Scene')),
        'artboard opening_key: no state machine Scene',
      ),
      'another view-model name': (
        _changed('opening_key', (s) => _spec(s, viewModel: 'Scene')),
        'artboard opening_key: view model Panel, not Scene',
      ),
      'a missing Boolean': (
        _changed(
          'opening_key',
          (s) => _spec(
            s,
            properties: {...s.properties, 'driver': DataType.boolean},
          ),
        ),
        'view model Panel: driver is missing, not boolean',
      ),
      'a Boolean expected as a number': (
        _changed(
          'opening_key',
          (s) =>
              _spec(s, properties: {...s.properties, 'usta': DataType.number}),
        ),
        'view model Panel: usta is boolean, not number',
      ),
    };
    for (final MapEntry(key: name, value: (contract, problem))
        in cases.entries) {
      test(name, () {
        final art = checkRiveArt(file, contract);
        expect(art.problems, ['$_prefix$problem']);
        expect(art.usable, _others);
      });
    }

    test('an artboard name the file lacks', () {
      final contract = RiveContract(
        asset: sceneContract.asset,
        artboards: {
          ...sceneContract.artboards,
          'opening_nope': sceneContract.artboards['opening_key']!,
        },
        known: sceneContract.known,
      );
      final art = checkRiveArt(file, contract);
      expect(art.problems, ['${_prefix}artboard opening_nope: missing']);
      expect(art.usable, {...scenePanelSlugs});
    });

    test('Tuktuk not known: a problem, and all six panels stay usable', () {
      final contract = RiveContract(
        asset: sceneContract.asset,
        artboards: sceneContract.artboards,
        known: {...sceneContract.known}..remove('Tuktuk'),
      );
      final art = checkRiveArt(file, contract);
      expect(art.problems, ['${_prefix}artboard Tuktuk: not in the contract']);
      expect(art.usable, {...scenePanelSlugs});
    });
  });

  testWidgets('loads from the bundle, as boot does', (tester) async {
    final art = await tester.runAsync(
      () => loadRiveArt(contract: sceneContract),
    );
    addTearDown(() => art?.file?.dispose());
    expect(art!.file, isNotNull, reason: '${art.problems}');
    expect(art.usable, sceneContract.artboards.keys.toSet());
  });

  testWidgets('a check that throws: every panel its drawing, never a failed '
      'boot', (tester) async {
    final art = await tester.runAsync(
      () => loadRiveArt(
        contract: sceneContract,
        check: (_) => throw StateError('broken'),
      ),
    );
    expect(art!.file, isNull);
    expect(art.problems, [
      allOf(startsWith('assets/rive/wassal_scenes.riv: '), contains('broken')),
    ]);
  });
}
