import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/economy/domain/txn_id.dart';

void main() {
  test('parse accepts a lowercase UUIDv7', () {
    const id = '0192f3a1-7b2c-7d4e-8f00-123456789abc';
    expect(TxnId.parse(id).value, id);
    expect(TxnId.parse(id), TxnId.parse(id));
    expect(TxnId.parse(id).toString(), id);
  });

  test('parse refuses anything else', () {
    for (final bad in [
      '0192f3a1-7b2c-4d4e-8f00-123456789abc', // v4
      '0192F3A1-7B2C-7D4E-8F00-123456789ABC', // uppercase
      '0192f3a17b2c-7d4e-8f00-123456789abc', // a missing hyphen
      '0192f3a1-7b2c-7d4e-cf00-123456789abc', // a bad variant
      '',
    ]) {
      expect(() => TxnId.parse(bad), throwsFormatException, reason: bad);
    }
  });
}
