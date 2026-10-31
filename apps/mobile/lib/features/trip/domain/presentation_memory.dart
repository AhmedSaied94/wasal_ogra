// What the screen remembers next to the engine (data-model.md "Presentation
// memory"): folded from each step's and each command's events by pure
// functions, never saved. A rebuild starts it empty.
import 'package:content_models/content_models.dart';
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/features/trip/domain/bubble_queue.dart';
import 'package:wassal/features/trip/domain/cues.dart';
import 'package:wassal/features/trip/domain/rider_comments.dart';
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

/// What بلية would say now: a coach step's line or a hint, and what it is
/// for, so a new line of the same step keeps its bubble.
typedef BelyaWish = ({Object source, ViewValue line});

/// A story rider's line in the character slot, as the content wrote it.
final class RiderLine extends ViewValue {
  const RiderLine(this.text);

  final String text;

  @override
  Map<String, Object?> get fields => {'text': text};
}

/// The character slot's bubble: بلية's (specs/012-m07-onboarding/contracts/
/// coach.md "بلية's bubble") or a story rider's comment (specs/015-m10-
/// apartment-story, contracts/story-trip.md "Timing"). One of the two
/// bubbles, up for at least its minimum time.
final class CharacterBubble extends ViewValue {
  const CharacterBubble({
    required this.speaker,
    required this.source,
    required this.line,
    required this.shownAtMs,
  });

  /// Who speaks: [StoryCharacter.belya] for بلية, else the rider.
  final StoryCharacter speaker;

  /// What the bubble is for: a coach step, a hint's key, or a rider comment.
  final Object source;

  /// A coach line (the onboarding's), a [HintView] or a [RiderLine].
  final ViewValue line;
  final int shownAtMs;

  @override
  Map<String, Object?> get fields => {
    'speaker': speaker,
    'source': source,
    'line': line,
    'shownAtMs': shownAtMs,
  };
}

/// A rider's comment waiting for the character slot, from its event's time.
final class WaitingComment extends ViewValue {
  const WaitingComment({required this.comment, required this.emittedAtMs});

  final RiderComment comment;
  final int emittedAtMs;

  @override
  Map<String, Object?> get fields => {
    'comment': comment.line,
    'speaker': comment.speaker,
    'ordinal': comment.ordinal,
    'emittedAtMs': emittedAtMs,
  };
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
    this.character,
    this.waitingComment,
    this.riderOrdinal = 0,
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

  /// The character slot's bubble (بلية's or a rider's), while it shows.
  final CharacterBubble? character;

  /// The latest rider comment, until it takes the slot or waits too long.
  final WaitingComment? waitingComment;

  /// How many rider comments the trip has had: the next one's ordinal.
  final int riderOrdinal;

  /// [events] and their [cues] folded in, at the clock [tMs] they end on.
  /// [riderComments] are the story riders' comments these events drew, in
  /// order (the controller picks them, with the trip's seed).
  PresentationMemory update(
    List<DomainEvent> events,
    List<TripCue> cues, {
    required int tMs,
    required int bubbleMinMs,
    List<RiderComment> riderComments = const [],
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
      bubbles: bubbles.at(
        tMs,
        bubbleMinMs: bubbleMinMs,
        reserved: character == null ? 0 : 1,
      ),
      log: log,
      banner: banner,
      openRoad: openRoad,
      waveAtMs: waveAtMs,
      character: character,
      // Comments never pile up: the latest waits.
      waitingComment: riderComments.isEmpty
          ? waitingComment
          : WaitingComment(comment: riderComments.last, emittedAtMs: tMs),
      riderOrdinal: riderOrdinal + riderComments.length,
    );
  }

  /// The character slot at [tMs], given what بلية would say now ([wish]):
  /// - a bubble showing stays its minimum time; بلية's stays as long after
  ///   as its source still speaks, taking that source's latest line;
  /// - otherwise the slot goes to [wish], or without one to a rider's
  ///   waiting comment, when at most one passenger's bubble is up (بلية
  ///   wins a tie);
  /// - a comment that has waited past [bubbleMinMs] is dropped.
  PresentationMemory characterAt(
    BelyaWish? wish, {
    required int tMs,
    required int bubbleMinMs,
  }) {
    final current = character;
    var waiting = waitingComment;
    if (waiting != null && tMs - waiting.emittedAtMs > bubbleMinMs) {
      waiting = null;
    }
    final CharacterBubble? next;
    if (current != null &&
        current.speaker == StoryCharacter.belya &&
        current.source == wish?.source) {
      next = CharacterBubble(
        speaker: StoryCharacter.belya,
        source: current.source,
        line: wish!.line,
        shownAtMs: current.shownAtMs,
      );
    } else if (current != null && tMs - current.shownAtMs < bubbleMinMs) {
      next = current;
    } else if (bubbles.visible.length >= maxVisibleBubbles) {
      next = null;
    } else if (wish != null) {
      next = CharacterBubble(
        speaker: StoryCharacter.belya,
        source: wish.source,
        line: wish.line,
        shownAtMs: tMs,
      );
    } else if (waiting != null) {
      next = CharacterBubble(
        speaker: waiting.comment.speaker,
        source: waiting.comment,
        line: RiderLine(waiting.comment.line),
        shownAtMs: tMs,
      );
      waiting = null;
    } else {
      next = null;
    }
    if (next == current && waiting == waitingComment) return this;
    return PresentationMemory(
      walks: walks,
      warning: warning,
      bubbles: bubbles,
      log: log,
      banner: banner,
      openRoad: openRoad,
      waveAtMs: waveAtMs,
      character: next,
      waitingComment: waiting,
      riderOrdinal: riderOrdinal,
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
    'character': character,
    'waitingComment': waitingComment,
    'riderOrdinal': riderOrdinal,
  };
}
