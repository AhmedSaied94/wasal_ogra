// The server's times: ISO-8601 UTC with `Z`, to the second or to the
// millisecond (B03 contracts/api.md, `wallets.iso`). The app counts in
// integer milliseconds (constitution II).
import 'package:wassal/core/sync/domain/wire/reader.dart';

final _utc = RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?Z$');

/// [text] in UTC milliseconds. Throws [WireFormatException] unless it is
/// ISO-8601 UTC with `Z`. Sub-millisecond digits are dropped.
int isoToMs(String text) {
  if (!_utc.hasMatch(text)) {
    throw WireFormatException('not an ISO-8601 UTC time: $text');
  }
  final parsed = DateTime.tryParse(text);
  if (parsed == null) throw WireFormatException('not a valid time: $text');
  return parsed.millisecondsSinceEpoch;
}

/// [ms] as ISO-8601 UTC with milliseconds and `Z`, as `occurred_at` is sent.
String msToIso(int ms) =>
    DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toIso8601String();

extension WireTimes on WireObject {
  int time(String key) => isoToMs(string(key));

  int? optionalTime(String key) => has(key) ? time(key) : null;
}
