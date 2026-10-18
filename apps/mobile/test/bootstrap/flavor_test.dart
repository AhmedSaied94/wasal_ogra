import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/bootstrap/flavor.dart';

void main() {
  test('maps every build flavor name', () {
    expect(Flavor.fromName('dev'), Flavor.dev);
    expect(Flavor.fromName('staging'), Flavor.staging);
    expect(Flavor.fromName('prod'), Flavor.prod);
  });

  test('a missing flavor fails loudly', () {
    expect(() => Flavor.fromName(null), throwsStateError);
  });

  test('an unknown flavor fails loudly', () {
    expect(() => Flavor.fromName('production'), throwsStateError);
    expect(() => Flavor.fromName('DEV'), throwsStateError);
  });
}
