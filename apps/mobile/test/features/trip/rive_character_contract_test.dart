// The owner's character file matches its contract (tasks.md T058,
// contracts/rive-character.md "Tests"). It fails until
// `assets/rive/passenger.riv` is committed (owner action T059). Needs Rive's
// Linux library: `fvm dart run rive_native:setup --clean --platform linux`.
@Tags(['rive'])
library;

import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:rive/rive.dart';
import 'package:wassal/features/trip/domain/skin_looks.dart';
import 'package:wassal/features/trip/presentation/scene/rive_passenger_art.dart';

/// Under 300 KB (contracts/rive-character.md "Export").
const _maxBytes = 300 * 1024;

const _properties = {
  'mood': DataType.number,
  'talking': DataType.boolean,
  'asleep': DataType.boolean,
  'headphones': DataType.boolean,
  'alight': DataType.trigger,
  'shirt': DataType.color,
  'accessory': DataType.enumType,
};

void main() {
  setUpAll(RiveNative.init);

  test('passenger.riv has the artboard, machine and view model', () async {
    final asset = io.File(passengerRiveAsset);
    expect(
      asset.existsSync(),
      isTrue,
      reason: 'The owner commits $passengerRiveAsset (tasks.md T059).',
    );
    final bytes = asset.readAsBytesSync();
    expect(bytes.length, lessThan(_maxBytes));

    final file = await File.decode(bytes, riveFactory: Factory.flutter);
    expect(file, isNotNull);
    addTearDown(file!.dispose);
    final artboard = file.artboard(riveArtboardName);
    expect(artboard, isNotNull, reason: 'artboard $riveArtboardName');
    addTearDown(artboard!.dispose);
    final machine = artboard.stateMachine(riveStateMachineName);
    expect(machine, isNotNull, reason: 'state machine $riveStateMachineName');
    addTearDown(machine!.dispose);

    final model = file.viewModelByName(riveViewModelName);
    expect(model, isNotNull, reason: 'view model $riveViewModelName');
    addTearDown(model!.dispose);
    expect(file.defaultArtboardViewModel(artboard)?.name, riveViewModelName);
    expect({
      for (final property in model.properties) property.name: property.type,
    }, _properties);

    final instance = model.createDefaultInstance() ?? model.createInstance();
    expect(instance, isNotNull);
    addTearDown(instance!.dispose);
    final accessory = instance.enumerator('accessory')!;
    final values = file.enums
        .firstWhere((e) => e.name == accessory.enumType)
        .values;
    expect(values.toSet(), {for (final a in Accessory.values) a.name});
    expect(values, hasLength(Accessory.values.length));
  });
}
