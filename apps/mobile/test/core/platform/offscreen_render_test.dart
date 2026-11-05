// Drawing a widget to a PNG off screen (specs/015-m10-apartment-story
// contracts/scene-viewer.md "Share", T080): the render M08's share card
// took, now general. The result's own share tests (features/result/
// share_action_test.dart) keep the card's output pinned at 1080×1080.
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/platform/offscreen_render.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';

import '../../helpers/design_component.dart';

/// [png]'s width and height, from its header.
(int, int) _sizeOf(Uint8List png) {
  final header = ByteData.sublistView(png);
  // The signature (8), the IHDR's length and type (8), then the size.
  return (header.getUint32(16), header.getUint32(20));
}

Future<Color> _colorAt(WidgetTester tester, Uint8List png, int x, int y) async {
  final pixels = await tester.runAsync(() async {
    final codec = await ui.instantiateImageCodec(png);
    final image = (await codec.getNextFrame()).image;
    final data = await image.toByteData();
    final width = image.width;
    image.dispose();
    return (data!, width);
  });
  final (data, width) = pixels!;
  final rgba = data.getUint32((y * width + x) * 4);
  return Color(((rgba & 0xFF) << 24) | (rgba >> 8));
}

/// The picture the tests draw: `sun` on the left half, `ink` on the right.
const _picture = Row(
  textDirection: TextDirection.ltr,
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    Expanded(child: ColoredBox(color: ColorTokens.sun)),
    Expanded(child: ColoredBox(color: ColorTokens.ink)),
  ],
);

const _size = Size(358, 540);

Future<Uint8List> _render(WidgetTester tester, {double? pixelRatio}) async {
  await pumpDesignComponent(tester, const SizedBox(key: Key('anchor')));
  final context = tester.element(find.byKey(const Key('anchor')));
  Future<Uint8List> draw() => pixelRatio == null
      ? renderOffscreenPng(context, _picture, _size)
      : renderOffscreenPng(context, _picture, _size, pixelRatio: pixelRatio);
  Uint8List? png;
  unawaited(draw().then((value) => png = value));
  for (var i = 0; i < 100 && png == null; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  return png ?? fail('the render never finished');
}

/// A bundle whose loads wait for [gate]. Under `flutter test` an SVG's load
/// otherwise answers at once, so nothing is ever still loading, as it is on a
/// phone.
class _HeldBundle extends CachingAssetBundle {
  final gate = Completer<void>();

  @override
  Future<ByteData> load(String key) async {
    await gate.future;
    return rootBundle.load(key);
  }
}

void main() {
  // The crash on the phone: the cache answers a picture it holds with a
  // SynchronousFuture, and Future.wait, still waiting on one earlier picture,
  // fails with "Null check operator used on a null value".
  testWidgets('a cached picture right after one still loading', (tester) async {
    await pumpDesignComponent(tester, const SizedBox(key: Key('anchor')));
    final context = tester.element(find.byKey(const Key('anchor')));
    svg.cache.clear();
    addTearDown(svg.cache.clear);
    final held = _HeldBundle();
    final loading = SvgAssetLoader('assets/icons/star.svg', assetBundle: held);
    const cached = SvgAssetLoader('assets/icons/coin.svg');
    await tester.runAsync(
      () => svg.cache.putIfAbsent(
        cached.cacheKey(context),
        () => cached.loadBytes(context),
      ),
    );

    await tester.runAsync(() async {
      final done = loadSvgPictures(context, [loading, cached]);
      held.gate.complete();
      await done;
    });

    expect(svg.cache.count, 2);
  });

  testWidgets('358×540 at ×3 is a 1074×1620 PNG, drawn', (tester) async {
    final png = await _render(tester);
    expect(_sizeOf(png), (1074, 1620));
    expect(await _colorAt(tester, png, 10, 10), ColorTokens.sun);
    expect(await _colorAt(tester, png, 1060, 1600), ColorTokens.ink);
  });

  testWidgets('the ratio is the caller\'s', (tester) async {
    final png = await _render(tester, pixelRatio: 1);
    expect(_sizeOf(png), (358, 540));
  });

  testWidgets('the picture is taken off the screen again', (tester) async {
    await _render(tester);
    expect(find.byType(ColoredBox, skipOffstage: false), findsWidgets);
    // Nothing of the render is left in the overlay.
    final remaining = tester.widgetList<ColoredBox>(
      find.byType(ColoredBox, skipOffstage: false),
    );
    expect(remaining.where((box) => box.color == ColorTokens.ink), isEmpty);
  });
}
