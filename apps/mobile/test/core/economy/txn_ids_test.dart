import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/economy/txn_ids.dart';

import '../../helpers/economy.dart';

void main() {
  test('newTxnId is a UUIDv7 whose first 48 bits are the trusted time', () {
    final id = newTxnId(testEpochMs);
    final hex = id.value.replaceAll('-', '').substring(0, 12);
    expect(int.parse(hex, radix: 16), testEpochMs);
  });

  test('10,000 ids in the same millisecond are distinct', () {
    const count = 10000;
    final ids = {for (var i = 0; i < count; i++) newTxnId(testEpochMs)};
    expect(ids, hasLength(count));
  });
}
