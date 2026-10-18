/// How numbers are written (FR-025). Arabic-Indic is the default.
enum DigitStyle {
  arabicIndic('arabic_indic'),
  western('western');

  const DigitStyle(this.wire);

  /// The stored value of `pref.digit_style`.
  final String wire;

  /// Missing, unknown or non-string values fall back to [arabicIndic]
  /// (FR-027).
  static DigitStyle fromWire(Object? value) {
    for (final style in values) {
      if (style.wire == value) return style;
    }
    return arabicIndic;
  }
}
