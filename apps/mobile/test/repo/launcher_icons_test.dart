import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

// The launcher icons are direction أ's, as tool/design/gen_launcher_icons.sh
// writes them from docs/design/brand/ (specs/008.5-m21-design-refresh
// tasks.md T130): every Android density with its legacy icon and the
// adaptive icon's three layers, and every iOS size, opaque.

const _res = 'android/app/src/main/res';
const _ios = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';

const _densities = {
  'mdpi': 1.0,
  'hdpi': 1.5,
  'xhdpi': 2.0,
  'xxhdpi': 3.0,
  'xxxhdpi': 4.0,
};

/// A PNG's size and whether it has an alpha channel, from its header.
({int width, int height, bool alpha}) _png(String path) {
  final bytes = File(path).readAsBytesSync();
  final header = ByteData.sublistView(bytes, 0, 26);
  expect(bytes.sublist(1, 4), utf8.encode('PNG'), reason: '$path is not a PNG');
  final colorType = header.getUint8(25);
  return (
    width: header.getUint32(16),
    height: header.getUint32(20),
    // Grey with alpha, or RGBA.
    alpha: colorType == 4 || colorType == 6,
  );
}

void _expectSquare(String path, int side) {
  expect(File(path).existsSync(), isTrue, reason: '$path is missing');
  final png = _png(path);
  expect((png.width, png.height), (side, side), reason: path);
}

void main() {
  for (final MapEntry(key: density, value: scale) in _densities.entries) {
    test('mipmap-$density: the legacy icon and the three layers', () {
      final dir = '$_res/mipmap-$density';
      _expectSquare('$dir/ic_launcher.png', (48 * scale).round());
      for (final layer in ['background', 'foreground', 'monochrome']) {
        _expectSquare('$dir/ic_launcher_$layer.png', (108 * scale).round());
      }
    });
  }

  test('the adaptive icon names its three layers', () {
    final xml = File('$_res/mipmap-anydpi-v26/ic_launcher.xml')
        .readAsStringSync();
    for (final layer in ['background', 'foreground', 'monochrome']) {
      expect(
        xml,
        contains('<$layer android:drawable="@mipmap/ic_launcher_$layer" />'),
      );
    }
  });

  test('every iOS size is there, at its pixels, opaque', () {
    final contents = jsonDecode(
      File('$_ios/Contents.json').readAsStringSync(),
    ) as Map<String, Object?>;
    final images = (contents['images']! as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(images, isNotEmpty);
    for (final image in images) {
      final side = double.parse((image['size']! as String).split('x').first);
      final scale = int.parse((image['scale']! as String).replaceAll('x', ''));
      final path = '$_ios/${image['filename']}';
      _expectSquare(path, (side * scale).round());
      expect(_png(path).alpha, isFalse, reason: '$path must be opaque');
    }
  });

  test("the Play listing's icon: 512×512, opaque", () {
    const path = '../../docs/design/brand/store_icon_512.png';
    _expectSquare(path, 512);
    expect(_png(path).alpha, isFalse);
  });
}
