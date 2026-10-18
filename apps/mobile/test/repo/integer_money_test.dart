import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_source.dart';

// Money is integer piasters (constitution II). No parameter, field,
// variable or return type with a money name may be a double or num.

final _floatDeclaration = RegExp(r'\b(?:double|num)\??\s+(?:get\s+)?(\w+)');
final _moneyName = RegExp(
  'piaster|amount|price|fare|cash|money|jenehat|bonat',
  caseSensitive: false,
);

List<String> floatMoney(String source) {
  final lines = stripComments(source).split('\n');
  return [
    for (var i = 0; i < lines.length; i++)
      for (final match in _floatDeclaration.allMatches(lines[i]))
        if (_moneyName.hasMatch(match[1]!)) '${i + 1}: ${lines[i].trim()}',
  ];
}

void main() {
  test('lib/ declares no money as double or num', () {
    final violations = [
      for (final file in libDartFiles())
        for (final hit in floatMoney(file.readAsStringSync()))
          '${file.path}:$hit',
    ];
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test('NumberFormatter.piasters takes an int', () {
    final source = File('lib/core/l10n/number_formatter.dart')
        .readAsStringSync();
    expect(source, matches(RegExp(r'String piasters\(int \w+\)')));
  });

  test('the scan catches float money and ignores the rest', () {
    expect(floatMoney('void f(double amountPiasters) {}'), hasLength(1));
    expect(floatMoney('final num fare = 3;'), hasLength(1));
    expect(floatMoney('double? totalPrice;'), hasLength(1));
    expect(floatMoney('double get cashOnHand => 0;'), hasLength(1));
    expect(floatMoney('double priceOf(int x) => 0;'), hasLength(1));
    expect(floatMoney('final double opacity = 0.6;'), isEmpty);
    expect(floatMoney('int amountPiasters = 850;'), isEmpty);
    expect(floatMoney('// double amountPiasters'), isEmpty);
  });
}
