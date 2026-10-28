import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:rive/rive.dart' as rive;
import 'package:wassal/core/art/rive_art.dart';
import 'package:wassal/core/art/rive_scenes.dart';

// What each Rive file must hold (specs/012.5-m22-animated-scenes,
// data-model.md "RiveContract", contracts/rive-scenes.md "The contract"):
// the characters' file keeps 008.5's contract, the scenes' file has six
// panels, and a file that can't load names itself in its one problem.

const _panels = [
  'opening_key',
  'opening_stand',
  'opening_go',
  'stand_morning',
  'salma_waiting',
  'usta_decides',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final (name, contract) in [
    ('the characters', riveCharacterContract),
    ('the scenes', sceneContract),
  ]) {
    test("$name: artboards and known are disjoint", () {
      expect(
        contract.known.intersection(contract.artboards.keys.toSet()),
        isEmpty,
      );
    });
  }

  test("the characters' contract is 008.5's", () {
    expect(riveCharacterContract.asset, riveArtAsset);
    expect(riveCharacterContract.artboards, same(riveContract));
    expect(riveCharacterContract.known, same(riveExportArtboards));
  });

  test('the scenes: six 358×540 panels, each with Panel and four Booleans', () {
    expect(sceneContract.asset, 'assets/rive/wassal_scenes.riv');
    expect(sceneContract.artboards.keys, orderedEquals(_panels));
    for (final MapEntry(key: slug, value: spec)
        in sceneContract.artboards.entries) {
      expect(spec.size, const Size(358, 540), reason: slug);
      expect(spec.machine, 'Panel', reason: slug);
      expect(spec.viewModel, 'Panel', reason: slug);
      expect(spec.properties, {
        'moallem': rive.DataType.boolean,
        'usta': rive.DataType.boolean,
        'belya': rive.DataType.boolean,
        'salma': rive.DataType.boolean,
      }, reason: slug);
    }
  });

  test("the scenes: the building blocks and the export's own are known", () {
    expect(sceneContract.known, {
      'Character_usta',
      'Character_moallem',
      'Character_belya',
      'Character_salma',
      'Prop_tin',
      'Prop_key',
      'Prop_drawer',
      'Prop_busstop',
      'Prop_books',
      'Prop_bag',
      'Tuktuk',
      'Artboard 1',
      'Watermark',
      'NuRiveBrandmark01',
      'NuRiveWordmark01',
    });
  });

  test('a contract refuses an artboard both drawn and known', () {
    final spec = sceneContract.artboards['opening_key']!;
    expect(
      () => RiveContract(
        asset: 'assets/rive/x.riv',
        artboards: {'A': spec},
        known: const {'A'},
      ),
      throwsA(isA<AssertionError>()),
    );
  });

  test('a missing scenes file: no panel animates, and its one problem '
      'names it', () async {
    final art = await loadRiveArt(
      contract: sceneContract,
      asset: 'assets/rive/missing.riv',
    );
    expect(art.file, isNull);
    expect(art.usable, isEmpty);
    expect(art.problems.single, startsWith('assets/rive/missing.riv: '));
    expect(ScenePanels.of(art).animates('opening_key'), isFalse);
  });

  test('ScenePanels: a panel animates only with a file and its artboard '
      'passed', () {
    expect(const ScenePanels.none().animates('opening_key'), isFalse);
    expect(ScenePanels.of(null).animates('opening_key'), isFalse);
    // No file: nothing animates, whatever passed.
    expect(
      ScenePanels.of(
        const RiveArt(file: null, usable: {'opening_key'}, problems: []),
      ).animates('opening_key'),
      isFalse,
    );
    const some = ScenePanels({'opening_stand'});
    expect(some.animates('opening_stand'), isTrue);
    expect(some.animates('opening_key'), isFalse);
  });
}
