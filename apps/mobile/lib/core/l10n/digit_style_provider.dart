import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wassal/bootstrap/startup.dart';
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/core/l10n/number_formatter.dart';

part 'digit_style_provider.g.dart';

/// The player's digit style, kept on the device (FR-025 – FR-027).
@Riverpod(keepAlive: true)
class DigitStyleNotifier extends _$DigitStyleNotifier {
  static const key = 'pref.digit_style';

  @override
  DigitStyle build() => DigitStyle.fromWire(
    ref.watch(settingsStoreProvider).requireValue.readString(key),
  );

  /// Applies [style] at once, then persists it.
  Future<void> set(DigitStyle style) async {
    state = style;
    await ref
        .read(settingsStoreProvider)
        .requireValue
        .writeString(key, style.wire);
  }
}

/// The formatter for the current style. Watchers rebuild when it changes
/// (FR-026).
@Riverpod(keepAlive: true)
NumberFormatter numberFormatter(Ref ref) =>
    NumberFormatter(ref.watch(digitStyleProvider));
