# Contract: Number Formatting

Spec FR-025 – FR-029; constitution II and X. Every number the player sees goes through
`NumberFormatter`. No widget calls `toString()`, string interpolation or `intl`'s `NumberFormat` on a
number it shows.

## API

```dart
enum DigitStyle { arabicIndic, western }

final class NumberFormatter {
  const NumberFormatter(DigitStyle style);
  String integer(int value);              // grouping + true minus sign
  String piasters(int amount);            // integer piasters → pounds
  String ratio(int part, int whole);      // 4/5
  String countdown(Duration remaining);   // m:ss, or h:mm:ss at one hour or more
}
```

- Widgets get the formatter for the current style from a provider. Changing the style rebuilds every
  watcher (FR-026).
- **Money input:** `piasters` accepts `int` only (constitution II). An amount that is not a multiple of
  50 is a programming error: it asserts in debug builds, and release builds show two decimals.
- **Output wrapping:** every result is wrapped in an LTR isolate (U+2066 … U+2069). The sign, digits and
  separators then keep their order inside Arabic sentences in both styles (FR-029).
- **No Arabic literals:** the Arabic-Indic digits and separators are built from code points
  (U+0660–U+0669, U+066B, U+066C), never typed as literals. This keeps the "no Arabic in source" check
  green (FR-042).

## Characters

| Part | Arabic-Indic | Western |
| --- | --- | --- |
| Digits | ٠١٢٣٤٥٦٧٨٩ (U+0660–U+0669) | 0123456789 |
| Decimal separator | ٫ (U+066B) | . |
| Thousands separator | ٬ (U+066C), from 1,000 up | , |
| Minus | − (U+2212) | − (U+2212) |
| Ratio separator | / | / |
| Time separator | : | : |

## Golden examples (the formatter unit tests assert exactly these, without the isolate marks)

| Call | Arabic-Indic | Western |
| --- | --- | --- |
| `integer(0)` | ٠ | 0 |
| `integer(7)` | ٧ | 7 |
| `integer(-1)` | −١ | −1 |
| `integer(1250)` | ١٬٢٥٠ | 1,250 |
| `integer(999)` | ٩٩٩ | 999 |
| `integer(1000000)` | ١٬٠٠٠٬٠٠٠ | 1,000,000 |
| `piasters(850)` | ٨٫٥ | 8.5 |
| `piasters(700)` | ٧ | 7 |
| `piasters(50)` | ٠٫٥ | 0.5 |
| `piasters(125000)` | ١٬٢٥٠ | 1,250 |
| `piasters(-850)` | −٨٫٥ | −8.5 |
| `ratio(4, 5)` | ٤/٥ | 4/5 |
| `countdown(750 s)` | ١٢:٣٠ | 12:30 |
| `countdown(65 s)` | ١:٠٥ | 1:05 |
| `countdown(3725 s)` | ١:٠٢:٠٥ | 1:02:05 |
| `countdown(-5 s)` | ٠:٠٠ (clamped) | 0:00 |

## Numbers inside ARB messages

- ARB placeholders that show numbers are declared as `String`, and the caller passes formatter output.
  Example: `"stationCount": "{count} محطات"`, with `count` typed `String`.
- Plural or select messages also take the raw `int` (for example `n`), used only to pick the form. They
  never print `{n}` directly.
- A test scans the ARB file and fails if a placeholder of type `int`, `num` or `double` appears in
  message text (outside plural or select selectors).
