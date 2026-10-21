import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/content/decode_pack_file.dart';
import 'package:wassal/features/boot/boot_screen.dart';

import '../../helpers/content.dart';
import '../../helpers/pump_app.dart';

const _bootError = 'حصلت مشكلة وإحنا بنفتح اللعبة.';
const _bootRetry = 'حاول تاني';

void main() {
  testWidgets('the boot screen waits for content, then hands over to Home', (
    tester,
  ) async {
    final gate = Completer<void>();
    await pumpWassalApp(
      tester,
      content: contentTestOverrides(
        decoder: (bytes, expected) async {
          await gate.future;
          return decodePackFile(bytes, expected);
        },
      ),
    );
    expect(currentLocation(tester), '/boot');

    gate.complete();
    await tester.pumpAndSettle();
    expect(currentLocation(tester), '/home');
    expect(find.byType(BootScreen), findsNothing);
  });

  testWidgets('a damaged bundled pack shows the retry, and retry recovers', (
    tester,
  ) async {
    final assets = sampleBundledAssets();
    final good = assets[sampleBundledFileAsset]!;
    final damaged = Uint8List.fromList(good)..[200] ^= 0x01;
    assets[sampleBundledFileAsset] = damaged;

    await pumpWassalApp(tester, content: contentTestOverrides(assets: assets));
    expect(currentLocation(tester), '/boot');
    expect(find.text(_bootError), findsOneWidget);
    expect(find.text(_bootRetry), findsOneWidget);

    assets[sampleBundledFileAsset] = good;
    await tester.tap(find.text(_bootRetry));
    await tester.pumpAndSettle();
    expect(currentLocation(tester), '/home');
  });
}
