import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/features/onboarding/domain/name_rules.dart';

// The rules the phone checks a name by (specs/012-m07-onboarding/contracts/
// name.md "NameRules", research R7). The filter list stays the server's.

void main() {
  NameCheck check(String raw) => NameRules.check(raw);

  group('normalizes', () {
    test('trims the ends', () {
      expect(check('  حمادة \t'), const NameOk('حمادة'));
    });

    test('collapses every run of whitespace inside to one space', () {
      expect(check('سيد   \n  الأسطى'), const NameOk('سيد الأسطى'));
      expect(check('سيد\u00A0\u00A0بلية'), const NameOk('سيد بلية'));
    });
  });

  group('empty', () {
    test('for nothing, and for spaces only', () {
      expect(check(''), const NameEmpty());
      expect(check('    '), const NameEmpty());
      expect(check(' \t\n '), const NameEmpty());
    });
  });

  group('length, in grapheme clusters', () {
    test('1 is too short, 2 is ok', () {
      expect(check('ع'), const NameTooShort());
      expect(check('ع ح'), const NameOk('ع ح'));
      expect(check('عم'), const NameOk('عم'));
    });

    test('a letter with its marks counts as one', () {
      // «س\u064F»: a letter and a damma, one cluster.
      expect(check('س\u064F'), const NameTooShort());
    });

    test('16 is ok, 17 is too long', () {
      final sixteen = 'ا' * nameMaxLength;
      expect(check(sixteen), NameOk(sixteen));
      expect(check('$sixteenب'), const NameTooLong());
      expect(nameMinLength, 2);
      expect(nameMaxLength, 16);
    });
  });

  group('only digits', () {
    test('Western digits, with and without spaces', () {
      expect(check('12345'), const NameOnlyDigits());
      expect(check('12 34'), const NameOnlyDigits());
    });

    test('Arabic-Indic digits, both sets', () {
      expect(check('١٢٣'), const NameOnlyDigits());
      expect(check('١٢ ٣٤'), const NameOnlyDigits());
      expect(check('۱۲۳'), const NameOnlyDigits());
    });

    test('a name with a digit in it is ok', () {
      expect(check('ميدو 2'), const NameOk('ميدو 2'));
    });
  });

  group('bad characters', () {
    for (final (what, char) in [
      ('a control character', '\u0007'),
      ('a NUL', '\u0000'),
      ('a right-to-left mark', '\u200F'),
      ('a right-to-left override', '\u202E'),
      ('a zero-width joiner', '\u200D'),
      ('a zero-width space', '\u200B'),
      ('a byte order mark', '\uFEFF'),
      ('a private-use character', '\uE000'),
      ('a supplementary private-use character', '\u{F0001}'),
    ]) {
      test(what, () {
        expect(check('حما$charدة'), const NameBadCharacters());
      });
    }

    test('bad characters win over the length and digit checks', () {
      expect(check('\u200F'), const NameBadCharacters());
      expect(check('12\u202E3'), const NameBadCharacters());
    });
  });

  test('every refusal is a refusal, and ok carries the name', () {
    expect(check('حمادة').isOk, isTrue);
    expect(check('حمادة').normalizedOrNull, 'حمادة');
    for (final bad in ['', 'ع', '123', '\u200F', 'ا' * 17]) {
      expect(check(bad).isOk, isFalse, reason: bad);
      expect(check(bad).normalizedOrNull, isNull, reason: bad);
    }
  });
}
