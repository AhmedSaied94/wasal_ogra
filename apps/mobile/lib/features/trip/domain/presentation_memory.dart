// What the screen remembers next to the engine (data-model.md "Presentation
// memory"): folded from each step's and each command's events by pure
// functions, never saved. A rebuild starts it empty.
import 'package:content_models/content_models.dart';
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/features/trip/domain/bubble_queue.dart';
import 'package:wassal/features/trip/domain/cues.dart';
import 'package:wassal/features/trip/domain/talk_log.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';
import 'package:wassal/features/trip/domain/view_value.dart';

/// A walk in or out of the cabin (contracts/scene-layout.md "Motion").
const walkMs = 600;

/// The fare-increase banner: in, held 4 s, out (008.5 contracts/
/// trip-layout.md "Motion": the toast's 200 ms each way).
const bannerMs = 200 + 4000 + 200;

/// Someone waves from the roadside while they walk in, and a little after.
const waveMs = 2 * walkMs;

enum WalkKind { boarding, leaving }

final class Walk extends ViewValue {
  const Walk(this.kind, this.startMs);

  final WalkKind kind;
  final int startMs;

  @override
  Map<String, Object?> get fields => {'kind': kind, 'startMs': startMs};
}

/// The last `StationWarning`, until its station is reached.
final class WarningMemory extends ViewValue {
  const WarningMemory({required this.stationId, required this.owed});

  final String stationId;
  final Set<String> owed;

  @override
  Map<String, Object?> get fields => {'stationId': stationId, 'owed': owed};
}

final class PresentationMemory extends ViewValue {
  const PresentationMemory({
    this.walks = const {},
    this.warning,
    this.bubbles = BubbleQueue.empty,
    this.log = TalkLog.empty,
    this.banner,
    this.openRoad = false,
    this.waveAtMs,
  });

  static const empty = PresentationMemory();

  /// Passengers walking in or out, by id.
  final Map<String, Walk> walks;
  final WarningMemory? warning;
  final BubbleQueue bubbles;
  final TalkLog log;
  final BannerView? banner;

  /// An open road rushes until the next station, as traffic lasts until
  /// it in the engine.
  final bool openRoad;

  /// A roadside pickup's wave, from this clock time.
  final int? waveAtMs;

  /// [events] and their [cues] folded in, at the clock [tMs] they end on.
  PresentationMemory update(
    List<DomainEvent> events,
    List<TripCue> cues, {
    required int tMs,
    required int bubbleMinMs,
  }) {
    final walks = {
      for (final MapEntry(:key, :value) in this.walks.entries)
        if (tMs - value.startMs < walkMs) key: value,
    };
    var warning = this.warning;
    var openRoad = this.openRoad;
    var waveAtMs = this.waveAtMs;
    final disputing = <String>{};
    for (final event in events) {
      switch (event) {
        case DisputeRaised(:final passengerIds):
          disputing.addAll(passengerIds);
        case EventStarted(:final eventId):
          switch (eventId) {
            case EventId.openRoad:
              openRoad = true;
            case EventId.traffic:
              openRoad = false;
            case EventId.roadsidePickup:
              waveAtMs = event.tMs;
            default:
          }
        case PassengerBoarded(:final passengerId):
          walks[passengerId] = Walk(WalkKind.boarding, event.tMs);
        case PassengerAlighted(:final passengerId):
          walks[passengerId] = Walk(WalkKind.leaving, event.tMs);
        case StationWarning(:final stationId, :final owed):
          warning = WarningMemory(stationId: stationId, owed: owed.toSet());
        case StationReached():
          warning = null;
          openRoad = false;
        default:
      }
    }
    var bubbles = this.bubbles;
    var log = this.log;
    var banner = this.banner;
    for (final cue in cues) {
      switch (cue) {
        case LineCue(
          :final passengerId,
          :final speaker,
          :final text,
          :final style,
        ):
          bubbles = bubbles.push(
            WaitingLine(
              passengerId: passengerId,
              text: text,
              style: style,
              emittedAtMs: tMs,
            ),
          );
          log = log.push(
            LogLine(kind: LogKind.speech, speaker: speaker, text: text),
          );
        case LogCue(:final line):
          log = log.push(line);
        case BannerCue(:final oldPiasters, :final newPiasters):
          banner = BannerView(
            oldPiasters: oldPiasters,
            newPiasters: newPiasters,
            shownAtMs: tMs,
          );
        default:
      }
    }
    if (disputing.isNotEmpty) bubbles = bubbles.interrupt(disputing);
    if (banner != null && tMs - banner.shownAtMs >= bannerMs) banner = null;
    if (waveAtMs != null && tMs - waveAtMs >= waveMs) waveAtMs = null;
    return PresentationMemory(
      walks: walks,
      warning: warning,
      bubbles: bubbles.at(tMs, bubbleMinMs: bubbleMinMs),
      log: log,
      banner: banner,
      openRoad: openRoad,
      waveAtMs: waveAtMs,
    );
  }

  /// Only the clock moved: [update] with no events.
  PresentationMemory at(int tMs, {required int bubbleMinMs}) =>
      update(const [], const [], tMs: tMs, bubbleMinMs: bubbleMinMs);

  @override
  Map<String, Object?> get fields => {
    'walks': walks,
    'warning': warning,
    'bubbles': bubbles,
    'log': log,
    'banner': banner,
    'openRoad': openRoad,
    'waveAtMs': waveAtMs,
  };
}
