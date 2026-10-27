import 'package:wassal/core/l10n/digit_style.dart';

/// The only way a number reaches the screen (contracts/number-format.md).
///
/// Pure Dart. The Arabic-Indic characters are built from code points, so
/// this file holds no Arabic text (FR-042). Every result is wrapped in a
/// left-to-right isolate, so its sign, digits and separators keep their
/// order inside Arabic sentences (FR-029).
final class NumberFormatter {
  const NumberFormatter(this.style);

  final DigitStyle style;

  static const _isolateStart = '\u2066';
  static const _isolateEnd = '\u2069';
  static const _minus = '\u2212';
  static const _arabicZero = 0x0660;
  static final _arabicDecimal = String.fromCharCode(0x066B);
  static final _arabicThousands = String.fromCharCode(0x066C);

  /// Whole number with thousands grouping from 1,000 and a true minus sign.
  String integer(int value) => _isolate(_signed(value, _grouped(value.abs())));

  /// Integer piasters as pounds: 850 → 8.5, 700 → 7 (constitution II).
  ///
  /// Amounts move in 50-piaster steps; anything else is a programming
  /// error that asserts in debug and shows two decimals in release.
  String piasters(int amount) {
    assert(amount % 50 == 0, 'piasters must be a multiple of 50: $amount');
    final abs = amount.abs();
    final pounds = _grouped(abs ~/ 100);
    final rest = abs % 100;
    final String body;
    if (rest == 0) {
      body = pounds;
    } else if (rest % 10 == 0) {
      body = '$pounds$_decimal${_digits('${rest ~/ 10}')}';
    } else {
      body = '$pounds$_decimal${_digits(rest.toString().padLeft(2, '0'))}';
    }
    return _isolate(_signed(amount, body));
  }

  /// A part of a whole, such as 4/5.
  String ratio(int part, int whole) => _isolate(
    '${_signed(part, _grouped(part.abs()))}/'
    '${_signed(whole, _grouped(whole.abs()))}',
  );

  /// m:ss, or h:mm:ss from one hour. Negative durations show 0:00.
  String countdown(Duration remaining) {
    final total = remaining.isNegative ? 0 : remaining.inSeconds;
    final hours = total ~/ 3600;
    final minutes = (total % 3600) ~/ 60;
    final seconds = total % 60;
    String two(int n) => _digits(n.toString().padLeft(2, '0'));
    final text = hours > 0
        ? '${_digits('$hours')}:${two(minutes)}:${two(seconds)}'
        : '${_digits('$minutes')}:${two(seconds)}';
    return _isolate(text);
  }

  /// A time of day on a twelve-hour clock, h:mm, as Egyptian Arabic says
  /// it without a period: 16:30 → 4:30, 0:00 → 12:00.
  String clockTime(int hour, int minute) {
    final twelve = hour % 12 == 0 ? 12 : hour % 12;
    return _isolate(
      '${_digits('$twelve')}:${_digits(minute.toString().padLeft(2, '0'))}',
    );
  }

  String get _decimal => switch (style) {
    DigitStyle.arabicIndic => _arabicDecimal,
    DigitStyle.western => '.',
  };

  String get _thousands => switch (style) {
    DigitStyle.arabicIndic => _arabicThousands,
    DigitStyle.western => ',',
  };

  /// Groups a non-negative number in threes and maps its digits.
  String _grouped(int value) {
    final raw = value.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < raw.length; i++) {
      if (i > 0 && (raw.length - i) % 3 == 0) buffer.write(_thousands);
      buffer.write(raw[i]);
    }
    return _digits(buffer.toString());
  }

  /// Maps ASCII digits to the style's digits; other characters pass through.
  String _digits(String ascii) => switch (style) {
    DigitStyle.western => ascii,
    DigitStyle.arabicIndic => String.fromCharCodes(
      ascii.codeUnits.map(
        (c) => c >= 0x30 && c <= 0x39 ? _arabicZero + (c - 0x30) : c,
      ),
    ),
  };

  String _signed(int value, String body) => value < 0 ? '$_minus$body' : body;

  String _isolate(String text) => '$_isolateStart$text$_isolateEnd';
}
