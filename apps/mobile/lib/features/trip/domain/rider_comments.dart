// What a story rider says when the driver slips (specs/015-m10-apartment-
// story, contracts/story-trip.md "Comments", research R15). Pure: the pools
// are content and the pick is a fresh generator seeded from the trip's seed,
// so the engine's PRNG state is never read or advanced (constitution I, XII)
// and a replay shows the same lines at the same moments.
import 'package:content_models/content_models.dart';
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/features/trip/domain/speech.dart';

/// One comment: who says it, the line as the content wrote it, and its place
/// among the trip's rider comments.
final class RiderComment {
  const RiderComment({
    required this.speaker,
    required this.line,
    required this.ordinal,
  });

  final StoryCharacter speaker;
  final String line;
  final int ordinal;
}

/// The pool [cause] draws from in [comments], or null: only mistakes that
/// cost reputation have one. Over-change raises no `ReputationChanged`, so it
/// never reaches here (constitution XI).
String? _poolOf(RiderComments comments, RepCause cause) => switch (cause) {
  RepCause.shortChange => comments.shortChange,
  RepCause.falseAccusation => comments.falseAccusation,
  RepCause.fight => comments.fight,
  RepCause.missedStop => comments.missedStop,
  RepCause.impatient => comments.impatient,
  RepCause.changeRequestDeclined ||
  RepCause.exactChange ||
  RepCause.liarCaught ||
  RepCause.revive => null,
};

/// The comment [event] draws from [info]'s riders, or null. The speaker is
/// the first rider, in order, whose pool for the cause the content has;
/// [ordinal] counts the trip's rider comments from 0.
RiderComment? riderComment(
  StoryTripInfo info,
  SpeechResolver speech,
  ReputationChanged event, {
  required int seed,
  required int ordinal,
}) {
  final variant = _pick(seed, ordinal);
  for (final rider in info.riders) {
    final comments = rider.comments;
    if (comments == null) continue;
    final key = _poolOf(comments, event.cause);
    if (key == null) continue;
    final line = speech.resolve(speechKey: key, variant: variant);
    if (line == null) continue;
    return RiderComment(speaker: rider.character, line: line, ordinal: ordinal);
  }
  return null;
}

/// The first value of `Xorshift32(seed ^ (ordinal + 1))`, which is 1 when
/// that state would be 0.
int _pick(int seed, int ordinal) {
  var state = (seed ^ (ordinal + 1)) & 0xFFFFFFFF;
  if (state == 0) state = 1;
  final (value, _) = Xorshift32(state).next();
  return value;
}
