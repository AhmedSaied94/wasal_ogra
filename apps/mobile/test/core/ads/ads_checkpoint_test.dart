import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/ads/ads_checkpoint.dart';
import 'package:wassal/core/ads/ads_service.dart';

// The between-trips checkpoint never keeps the player from a trip
// (specs/018-m11-ads, research R10; review M2): whatever the ads layer
// throws, the pass completes.

final class _Throwing implements AdsService {
  _Throwing(this.error);

  final Object error;

  @override
  Future<void> betweenTrips() async => throw error;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final error in <Object>[
    Exception('the SDK'),
    StateError('a provider not ready'),
  ]) {
    test('passes when the ads layer throws ${error.runtimeType}', () async {
      await expectLater(AdsCheckpoint(_Throwing(error)).pass(), completes);
    });
  }
}
