import 'package:flutter_test/flutter_test.dart';

import 'c_trip_check.dart';
import 'samples/c_trip.dart';

// `C-Trip` against its measured boxes (contracts/design-checks.md).

void main() {
  testWidgets('C-Trip: the boxes', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpCTrip(tester);
    expectCTripLayout(tester);
    semantics.dispose();
  });
}
