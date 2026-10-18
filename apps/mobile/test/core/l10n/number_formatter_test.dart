import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/core/l10n/number_formatter.dart';

// contracts/number-format.md «Golden examples» (FR-027 – FR-029).

const lri = '\u2066';
const pdi = '\u2069';

String strip(String s) => s.replaceAll(lri, '').replaceAll(pdi, '');

void main() {
  const arabic = NumberFormatter(DigitStyle.arabicIndic);
  const western = NumberFormatter(DigitStyle.western);

  // (call, Arabic-Indic, Western)
  final examples = <(String Function(NumberFormatter), String, String)>[
    ((f) => f.integer(0), '٠', '0'),
    ((f) => f.integer(7), '٧', '7'),
    ((f) => f.integer(-1), '−١', '−1'),
    ((f) => f.integer(1250), '١٬٢٥٠', '1,250'),
    ((f) => f.integer(999), '٩٩٩', '999'),
    ((f) => f.integer(1000000), '١٬٠٠٠٬٠٠٠', '1,000,000'),
    ((f) => f.piasters(850), '٨٫٥', '8.5'),
    ((f) => f.piasters(700), '٧', '7'),
    ((f) => f.piasters(50), '٠٫٥', '0.5'),
    ((f) => f.piasters(125000), '١٬٢٥٠', '1,250'),
    ((f) => f.piasters(-850), '−٨٫٥', '−8.5'),
    ((f) => f.ratio(4, 5), '٤/٥', '4/5'),
    ((f) => f.countdown(const Duration(seconds: 750)), '١٢:٣٠', '12:30'),
    ((f) => f.countdown(const Duration(seconds: 65)), '١:٠٥', '1:05'),
    ((f) => f.countdown(const Duration(seconds: 3725)), '١:٠٢:٠٥', '1:02:05'),
    ((f) => f.countdown(const Duration(seconds: -5)), '٠:٠٠', '0:00'),
  ];

  test('every golden example, in both styles', () {
    for (final (call, expectedArabic, expectedWestern) in examples) {
      expect(strip(call(arabic)), expectedArabic);
      expect(strip(call(western)), expectedWestern);
    }
  });

  test('Arabic-Indic output uses only the contract characters', () {
    // Digits U+0660–U+0669, ٫ U+066B, ٬ U+066C, − U+2212, / and :.
    expect(strip(arabic.integer(1234567890)).runes.toSet(), {
      for (var d = 0; d <= 9; d++) 0x0660 + d,
      0x066C,
    });
    expect(
      strip(arabic.piasters(150)),
      '${String.fromCharCode(0x0661)}'
      '${String.fromCharCode(0x066B)}${String.fromCharCode(0x0665)}',
    );
    expect(strip(arabic.integer(-5)).runes.first, 0x2212);
  });

  test('every result sits in a left-to-right isolate (FR-029)', () {
    for (final (call, _, _) in examples) {
      for (final f in [arabic, western]) {
        final raw = call(f);
        expect(raw.startsWith(lri), isTrue, reason: raw);
        expect(raw.endsWith(pdi), isTrue, reason: raw);
        expect(raw.substring(1, raw.length - 1), isNot(contains(lri)));
      }
    }
  });

  test('a piaster amount off the 50 grid is a programming error', () {
    expect(() => arabic.piasters(825), throwsA(isA<AssertionError>()));
    expect(() => western.piasters(-25), throwsA(isA<AssertionError>()));
  });

  test('countdown switches to hours at one hour', () {
    expect(
      strip(western.countdown(const Duration(minutes: 59, seconds: 59))),
      '59:59',
    );
    expect(strip(western.countdown(const Duration(hours: 1))), '1:00:00');
    expect(
      strip(western.countdown(const Duration(hours: 25, seconds: 1))),
      '25:00:01',
    );
  });
}
