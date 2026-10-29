// The line Lines opens on (specs/014-m09-lines-vehicles, data-model "The
// focus line", FR-010): Home's next trip's line, else the last current
// line, else the last unlocked one.
import 'package:content_models/content_models.dart';
import 'package:wassal/core/content/domain/content_source.dart';
import 'package:wassal/core/progress/domain/player_progress.dart';
import 'package:wassal/core/progress/domain/unlocks.dart';
import 'package:wassal/features/home/domain/next_trip.dart';

import 'package:wassal/features/lines/domain/line_standing.dart';

LineId? focusLine(ContentSource c, PlayerProgress p, NextTrip? next) {
  if (next != null && c.line(next.lineId) != null) return next.lineId;
  LineId? current;
  LineId? unlocked;
  for (final line in c.lines) {
    if (!lineUnlocked(c, p, line.lineId)) continue;
    unlocked = line.lineId;
    if (nextInLine(c, p, line.lineId) != null) current = line.lineId;
  }
  return current ?? unlocked;
}
