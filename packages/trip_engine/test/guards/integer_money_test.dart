// Constitution II and SC-007: no floating point anywhere in the engine. Money
// and time are integers, and the only division is `~/`.
import 'package:test/test.dart';

import 'source_scan.dart';

final _forbidden = <String, RegExp>{
  'double': RegExp(r'\bdouble\b'),
  'num': RegExp(r'\bnum\b'),
  'toDouble': RegExp(r'\.toDouble\('),
  '/ as an operator': RegExp(r'(?<!~)/'),
};

List<String> _violations(String code) => [
  for (final MapEntry(:key, :value) in _forbidden.entries)
    if (value.hasMatch(code)) key,
];

void main() {
  test('the guard catches each forbidden form', () {
    expect(_violations('final double x = 1;'), ['double']);
    expect(_violations('num y = 2;'), ['num']);
    expect(_violations('final z = a.toDouble();'), ['toDouble']);
    expect(_violations('final q = a / b;'), ['/ as an operator']);
    expect(_violations('final q = a ~/ b; final n = number;'), isEmpty);
    expect(
      _violations(
        stripped("// a / b double\nfinal s = 'a/b';", strings: false),
      ),
      isEmpty,
    );
  });

  for (final file in libSources()) {
    test('${file.path} is integer-only', () {
      final code = stripped(file.readAsStringSync(), strings: false);
      expect(_violations(code), isEmpty);
    });
  }
}
