// A passenger's line, from the content's speech pools (contracts/trip-view.md
// "Speech and bubbles"). The text is content, so it is resolved here; the
// amounts are formatted in the player's digit style by the caller's
// formatter.
import 'package:content_models/content_models.dart';
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';

final class SpeechResolver {
  const SpeechResolver({
    required this.pool,
    required this.piasters,
    required this.station,
  });

  /// The pool of a speech key, or null.
  final SpeechPool? Function(String speechKey) pool;

  /// An amount in the player's digit style.
  final String Function(int piasters) piasters;

  /// A station's name in the trip's line, or its letter without the line.
  final String Function(String stationId) station;

  /// The line [event] says, or null when its pool is missing or empty.
  String? lineOf(PassengerSpeaks event) {
    final lines = pool(event.speechKey)?.lines;
    if (lines == null || lines.isEmpty) return null;
    var text = lines[event.variant % lines.length].text.arEg;
    if (event.amountPiasters case final amount?) {
      text = text.replaceAll('{amount}', piasters(amount));
    }
    if (event.stationId case final stationId?) {
      text = text.replaceAll('{station}', station(stationId));
    }
    return text;
  }
}

/// A bubble's look by what the passenger says.
BubbleStyle bubbleStyleOf(SpeechSlot slot) => switch (slot) {
  SpeechSlot.stopNear ||
  SpeechSlot.wantsChange ||
  SpeechSlot.shortChange ||
  SpeechSlot.impatient ||
  SpeechSlot.dropMeHere ||
  SpeechSlot.changeRequest => BubbleStyle.warning,
  SpeechSlot.fight ||
  SpeechSlot.accused ||
  SpeechSlot.dispute ||
  SpeechSlot.missedStop => BubbleStyle.fight,
  SpeechSlot.thanks ||
  SpeechSlot.tip ||
  SpeechSlot.returnsExcess ||
  SpeechSlot.caught => BubbleStyle.thanks,
  _ => BubbleStyle.plain,
};
