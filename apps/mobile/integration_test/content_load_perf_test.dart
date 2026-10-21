// The device load budgets (specs/006-m04-content-loader/research.md R15,
// SC-002). CI doesn't run this (contracts/ci-checks.md). On a mid-range
// Android device:
//
//   fvm flutter drive --flavor dev --profile \
//     --driver=test_driver/integration_test.dart \
//     --target=integration_test/content_load_perf_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wassal/core/content/decode_pack_file.dart';

import '../test/helpers/content.dart';
import '../test/helpers/synthetic_packs.dart';

/// The median of 5 decodes through `Isolate.run`, after one warm-up, in ms.
Future<int> _medianMs(EncodedPack pack) async {
  Future<PackDecodeResult> decode() =>
      Isolate.run(() => decodePackFile(pack.bytes, pack.expected));
  expect(await decode(), isA<PackDecoded>());
  final times = <int>[];
  for (var i = 0; i < 5; i++) {
    final watch = Stopwatch()..start();
    await decode();
    times.add(watch.elapsedMilliseconds);
  }
  times.sort();
  return times[2];
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('packs decode within the device budgets', (tester) async {
    final (mvp, large) =
        await tester.runAsync(() async {
          // The dev flavor bundles the sample; the host's files aren't here.
          final data = await rootBundle.load(sampleBundledFileAsset);
          final sample = (jsonDecode(
            utf8.decode(gzip.decode(Uint8List.sublistView(data))),
          ) as Map<String, dynamic>).cast<String, Object?>();
          return (
            await _medianMs(mvpSizePack(sample: sample)),
            await _medianMs(twoMebibytePack(sample: sample)),
          );
        }) ??
        (-1, -1);
    binding.reportData = {'mvp_size_ms': mvp, 'two_mebibyte_ms': large};
    expect(mvp, inInclusiveRange(0, 500));
    expect(large, inInclusiveRange(0, 1500));
  });
}
