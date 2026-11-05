// The game day on the phone (specs/018-m11-ads, research R9): Cairo's
// calendar date, as the server's `game_date` gives it, without a timezone
// package. Egypt's rule since 2023: UTC+2, and UTC+3 from the last Friday of
// April 00:00 local to the last Thursday of October 24:00 local. The shared
// fixture `fixtures/economy/game_day.json` pins this to Python's
// `Africa/Cairo`, and both sides replay it, so a rule change fails CI.

const _hourMs = 60 * 60 * 1000;

/// The day of the month of the last [weekday] (`DateTime.monday`…) in
/// [month] of [year].
int _lastWeekday(int year, int month, int weekday) {
  // Day 0 of the next month is this month's last day.
  final last = DateTime.utc(year, month + 1, 0);
  return last.day - (last.weekday - weekday + 7) % 7;
}

/// Whether Cairo keeps summer time (UTC+3) at [ms].
bool _summer(int ms) {
  final year = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).year;
  final startDay = _lastWeekday(year, DateTime.april, DateTime.friday);
  final endDay = _lastWeekday(year, DateTime.october, DateTime.thursday);
  // 00:00 at UTC+2, and 24:00 at UTC+3.
  final start =
      DateTime.utc(year, 4, startDay).millisecondsSinceEpoch - 2 * _hourMs;
  final end =
      DateTime.utc(year, 10, endDay + 1).millisecondsSinceEpoch - 3 * _hourMs;
  return ms >= start && ms < end;
}

String _two(int n) => n < 10 ? '0$n' : '$n';

/// Cairo's date at [trustedMs], as `YYYY-MM-DD`.
String gameDayOf(int trustedMs) {
  final offset = (_summer(trustedMs) ? 3 : 2) * _hourMs;
  final local = DateTime.fromMillisecondsSinceEpoch(
    trustedMs + offset,
    isUtc: true,
  );
  return '${local.year}-${_two(local.month)}-${_two(local.day)}';
}
