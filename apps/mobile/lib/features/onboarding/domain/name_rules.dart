// The rules the phone checks the driver's name by (specs/012-m07-onboarding/
// contracts/name.md "NameRules", research R7): B03 R10's set with the
// design's 16 as the maximum. The phone does no NFKC (Dart's core libraries
// have none); the server normalizes before its own check, and the filter
// list stays the server's.
import 'package:characters/characters.dart';

/// The fewest grapheme clusters a name may have.
const nameMinLength = 2;

/// The most grapheme clusters a name may have. The name field stops here
/// too, so a paste is cut before the check.
const nameMaxLength = 16;

/// What [NameRules.check] says of a name.
sealed class NameCheck {
  const NameCheck();

  bool get isOk => this is NameOk;

  /// The name to store when it is [NameOk], else null.
  String? get normalizedOrNull => switch (this) {
    NameOk(:final normalized) => normalized,
    _ => null,
  };
}

/// The name passes, trimmed and with its inner whitespace collapsed.
final class NameOk extends NameCheck {
  const NameOk(this.normalized);

  final String normalized;

  @override
  bool operator ==(Object other) =>
      other is NameOk && other.normalized == normalized;

  @override
  int get hashCode => normalized.hashCode;

  @override
  String toString() => 'NameOk($normalized)';
}

/// Nothing is left after trimming.
final class NameEmpty extends NameCheck {
  const NameEmpty();

  @override
  bool operator ==(Object other) => other is NameEmpty;

  @override
  int get hashCode => 0;
}

/// Under [nameMinLength] grapheme clusters.
final class NameTooShort extends NameCheck {
  const NameTooShort();

  @override
  bool operator ==(Object other) => other is NameTooShort;

  @override
  int get hashCode => 1;
}

/// Over [nameMaxLength] grapheme clusters. The field never lets one
/// through; a name from anywhere else may.
final class NameTooLong extends NameCheck {
  const NameTooLong();

  @override
  bool operator ==(Object other) => other is NameTooLong;

  @override
  int get hashCode => 2;
}

/// Digits only, Western or Arabic-Indic, spaces aside.
final class NameOnlyDigits extends NameCheck {
  const NameOnlyDigits();

  @override
  bool operator ==(Object other) => other is NameOnlyDigits;

  @override
  int get hashCode => 3;
}

/// A control, format (bidi marks, zero-width joiners and spaces) or
/// private-use character.
final class NameBadCharacters extends NameCheck {
  const NameBadCharacters();

  @override
  bool operator ==(Object other) => other is NameBadCharacters;

  @override
  int get hashCode => 4;
}

abstract final class NameRules {
  /// Whitespace as the server's `\s` sees it (Python's `str.isspace`), not
  /// Dart's, which also counts U+FEFF: a byte order mark stays, and is
  /// refused as a format character, as the server refuses it.
  static final _whitespace = RegExp(
    '[\t\n\x0B\f\r\x1C-\x1F \x85\xA0\u1680\u2000-\u200A\u2028\u2029'
    '\u202F\u205F\u3000]+',
  );

  /// Checks [raw]: normalize, then empty, bad characters, digits only, too
  /// short, too long, in that order.
  static NameCheck check(String raw) {
    final normalized = raw.replaceAll(_whitespace, ' ').trimSpaces();
    if (normalized.isEmpty) return const NameEmpty();
    final runes = normalized.runes;
    if (runes.any(_isBad)) return const NameBadCharacters();
    if (runes.every((r) => r == _space || _isDigit(r))) {
      return const NameOnlyDigits();
    }
    final length = normalized.characters.length;
    if (length < nameMinLength) return const NameTooShort();
    if (length > nameMaxLength) return const NameTooLong();
    return NameOk(normalized);
  }
}

const _space = 0x20;

extension on String {
  /// Without the plain spaces at either end.
  String trimSpaces() {
    var start = 0;
    var end = length;
    while (start < end && codeUnitAt(start) == _space) {
      start++;
    }
    while (end > start && codeUnitAt(end - 1) == _space) {
      end--;
    }
    return substring(start, end);
  }
}

bool _isDigit(int r) =>
    (r >= 0x30 && r <= 0x39) ||
    (r >= 0x660 && r <= 0x669) ||
    (r >= 0x6F0 && r <= 0x6F9);

/// Unicode's Cc, Cf, Cs and Co, from the character database's ranges.
bool _isBad(int r) =>
    _isControl(r) || _isFormat(r) || _isSurrogate(r) || _isPrivateUse(r);

bool _isControl(int r) => r <= 0x1F || (r >= 0x7F && r <= 0x9F);

bool _isSurrogate(int r) => r >= 0xD800 && r <= 0xDFFF;

bool _isPrivateUse(int r) =>
    (r >= 0xE000 && r <= 0xF8FF) ||
    (r >= 0xF0000 && r <= 0xFFFFD) ||
    (r >= 0x100000 && r <= 0x10FFFD);

/// The general category Cf.
const _formatRanges = <(int, int)>[
  (0xAD, 0xAD),
  (0x600, 0x605),
  (0x61C, 0x61C),
  (0x6DD, 0x6DD),
  (0x70F, 0x70F),
  (0x890, 0x891),
  (0x8E2, 0x8E2),
  (0x180E, 0x180E),
  (0x200B, 0x200F),
  (0x202A, 0x202E),
  (0x2060, 0x2064),
  (0x2066, 0x206F),
  (0xFEFF, 0xFEFF),
  (0xFFF9, 0xFFFB),
  (0x110BD, 0x110BD),
  (0x110CD, 0x110CD),
  (0x13430, 0x1343F),
  (0x1BCA0, 0x1BCA3),
  (0x1D173, 0x1D17A),
  (0xE0001, 0xE0001),
  (0xE0020, 0xE007F),
];

bool _isFormat(int r) {
  for (final (from, to) in _formatRanges) {
    if (r >= from && r <= to) return true;
  }
  return false;
}
