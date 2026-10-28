// The result's quote (specs/013-m08-home-result, data-model `Quote`,
// research R14). The trip is replayed with the engine's public API, each
// logged command at its time as `playLog` applies them, and the lines said
// on the way are kept: a trip rebuilt after a kill quotes what one played
// straight through would. The text is resolved in presentation, from the
// speech pool, as the trip's bubbles are.
import 'package:content_models/content_models.dart';
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/features/result/domain/speaker.dart';
import 'package:wassal/features/trip/domain/looks.dart';

final class Quote {
  const Quote({
    required this.passengerId,
    required this.look,
    required this.labelKey,
    required this.speechKey,
    required this.variant,
    this.amountPiasters,
    this.stationId,
  });

  final String passengerId;
  final Look look;

  /// The ARB key of the speaker under the line.
  final String labelKey;
  final String speechKey;
  final int variant;
  final int? amountPiasters;
  final String? stationId;

  @override
  bool operator ==(Object other) =>
      other is Quote &&
      other.passengerId == passengerId &&
      other.look == look &&
      other.labelKey == labelKey &&
      other.speechKey == speechKey &&
      other.variant == variant &&
      other.amountPiasters == amountPiasters &&
      other.stationId == stationId;

  @override
  int get hashCode => Object.hash(
    passengerId,
    look,
    labelKey,
    speechKey,
    variant,
    amountPiasters,
    stationId,
  );

  @override
  String toString() => 'Quote($passengerId $speechKey#$variant)';
}

/// Everything said in [record]'s trip, in order, and the result it ends
/// with: null for a record the engine refuses.
({List<PassengerSpeaks> lines, TripResult? result}) replaySpeech(
  ReplayRecord record,
) {
  final TripEngine engine;
  try {
    engine = TripEngine.start(
      record.definition,
      record.params,
      seed: record.seed,
    );
  } on TripRefused {
    return (lines: const [], result: null);
  }
  final lines = <PassengerSpeaks>[];
  void keep(List<DomainEvent> events) =>
      lines.addAll(events.whereType<PassengerSpeaks>());
  for (final entry in record.commandLog) {
    keep(engine.stepTo(entry.tMs));
    if (engine.apply(entry.command) case Accepted(:final events)) keep(events);
  }
  while (engine.status == TripStatus.running) {
    keep(engine.step());
  }
  return (lines: lines, result: engine.result);
}

/// [record]'s quote, or null when nobody said a line worth quoting.
Quote? pickQuote(ReplayRecord record) =>
    quoteFrom(replaySpeech(record).lines, record.definition);

const _grateful = {SpeechSlot.thanks, SpeechSlot.tip};
const _payments = {SpeechSlot.pays, SpeechSlot.paysGroup, SpeechSlot.paysRest};
const _unhappy = {SpeechSlot.shortChange, SpeechSlot.fight, SpeechSlot.accused};

/// The last thanks or tip in [lines]; else the last payment from a
/// passenger who never said they were short, fought or were accused; else
/// null.
Quote? quoteFrom(Iterable<PassengerSpeaks> lines, TripDefinition trip) {
  final said = lines.toList();
  final unhappy = {
    for (final line in said)
      if (_unhappy.contains(line.slot)) line.passengerId,
  };
  final picked =
      said.lastWhereOrNull((l) => _grateful.contains(l.slot)) ??
      said.lastWhereOrNull(
        (l) => _payments.contains(l.slot) && !unhappy.contains(l.passengerId),
      );
  if (picked == null) return null;
  final speaker = speakerOf(trip, picked.passengerId);
  return Quote(
    passengerId: picked.passengerId,
    look: speaker.look,
    labelKey: speaker.labelKey,
    speechKey: picked.speechKey,
    variant: picked.variant,
    amountPiasters: picked.amountPiasters,
    stationId: picked.stationId,
  );
}

extension<T> on List<T> {
  T? lastWhereOrNull(bool Function(T item) test) {
    for (var i = length - 1; i >= 0; i--) {
      if (test(this[i])) return this[i];
    }
    return null;
  }
}
