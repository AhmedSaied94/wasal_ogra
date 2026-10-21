import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/content/client_version.dart';

ClientVersion _v(String text) => ClientVersion.parse(text)!;

void main() {
  test('the build is kept apart from the version', () {
    expect(_v('1.0.0'), _v('1.0.0+2'));
    expect(_v('1.0.0').build, isNull);
    expect(_v('1.0.0+2').build, 2);
    expect(_v('1.2.3+4').toString(), '1.2.3+4');
    expect(_v('1.2.3').toString(), '1.2.3');
  });

  test('malformed values are refused', () {
    for (final text in [
      '1.0',
      'v1.0.0',
      '1.0.0-beta',
      '',
      '1.0.0+',
      '1.0.0+b',
      '1..0',
      ' 1.0.0',
      '1.0.0.0',
    ]) {
      expect(ClientVersion.parse(text), isNull, reason: text);
    }
  });

  test('comparison is numeric, part by part', () {
    expect(_v('1.10.0').compareTo(_v('1.9.0')), greaterThan(0));
    expect(_v('2.0.0').compareTo(_v('1.99.99')), greaterThan(0));
    expect(_v('1.0.1').compareTo(_v('1.0.0')), greaterThan(0));
    expect(_v('1.0.0').compareTo(_v('1.0.0+9')), 0);
  });

  test('atLeast ignores the build', () {
    expect(_v('1.0.0+2').atLeast(_v('1.0.0')), isTrue);
    expect(_v('1.0.0').atLeast(_v('1.0.0+9')), isTrue);
    expect(_v('1.0.0+2').atLeast(_v('1.0.1')), isFalse);
    expect(_v('1.1.0').atLeast(_v('1.0.9')), isTrue);
  });
}
