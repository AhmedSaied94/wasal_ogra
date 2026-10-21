import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/platform/connectivity.dart';

void main() {
  test('any result but none is online', () {
    expect(isOnlineResult([ConnectivityResult.none]), isFalse);
    expect(isOnlineResult([]), isFalse);
    for (final result in ConnectivityResult.values) {
      if (result == ConnectivityResult.none) continue;
      expect(isOnlineResult([result]), isTrue, reason: result.name);
      expect(
        isOnlineResult([ConnectivityResult.none, result]),
        isTrue,
        reason: 'none plus ${result.name}',
      );
    }
  });
}
