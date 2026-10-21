import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/content/decode_pack_file.dart';

import '../../../helpers/content.dart';
import '../../../helpers/synthetic_packs.dart';

// The host-side load budgets (research R15, SC-002). The device budgets are
// in integration_test/content_load_perf_test.dart, which CI doesn't run.

/// The median time of [runs] decodes of [pack], after one warm-up.
Duration _median(EncodedPack pack, {int runs = 5}) {
  expect(decodePackFile(pack.bytes, pack.expected), isA<PackDecoded>());
  final times = [
    for (var i = 0; i < runs; i++)
      () {
        final watch = Stopwatch()..start();
        decodePackFile(pack.bytes, pack.expected);
        return watch.elapsed;
      }(),
  ]..sort();
  return times[runs ~/ 2];
}

void main() {
  test('an MVP-size pack decodes in under 300 ms', () {
    final pack = mvpSizePack();
    final decoded = decodePackFile(pack.bytes, pack.expected) as PackDecoded;
    expect(decoded.source.tripsOf(LineId.lineHay), hasLength(20));
    expect(decoded.source.tripsOf(LineId.lineGamaa), hasLength(30));
    expect(_median(pack), lessThan(const Duration(milliseconds: 300)));
  });

  test('a 2 MiB pack decodes in under 1,000 ms', () {
    final pack = twoMebibytePack();
    expect(pack.bytes.length, greaterThanOrEqualTo(2097152));
    expect(_median(pack), lessThan(const Duration(milliseconds: 1000)));
  });
}
