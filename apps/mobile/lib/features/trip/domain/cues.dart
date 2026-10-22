// One-shot effects of a step's or a command's events (contracts/trip-view.md
// "Cues"). Every key event reaches the player through more than one channel,
// so it still does with sound or vibration off (constitution XI).
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/features/trip/domain/speech.dart';
import 'package:wassal/features/trip/domain/talk_log.dart';
import 'package:wassal/features/trip/domain/trip_facts.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';
import 'package:wassal/features/trip/domain/view_value.dart';

/// The scene shakes this long on a bump or a fight.
const shakeMs = 300;

/// A passenger glows this long before the hand throws to them.
const highlightMs = 500;

/// The trip's effects, by the name of their stand-in file.
enum CueSound { coin, notePass, call, horn, fight, thanks, wrong, bump, alert }

enum HapticKind { light, heavy }

sealed class TripCue extends ViewValue {
  const TripCue();
}

final class SoundCue extends TripCue {
  const SoundCue(this.sound);

  final CueSound sound;

  @override
  Map<String, Object?> get fields => {'sound': sound};
}

final class HapticCue extends TripCue {
  const HapticCue(this.kind);

  final HapticKind kind;

  @override
  Map<String, Object?> get fields => {'kind': kind};
}

/// Skipped under reduced motion.
final class ShakeCue extends TripCue {
  const ShakeCue([this.durationMs = shakeMs]);

  final int durationMs;

  @override
  Map<String, Object?> get fields => {'durationMs': durationMs};
}

/// The half-second glow before a throw.
final class HighlightCue extends TripCue {
  const HighlightCue(this.passengerId);

  final String passengerId;

  @override
  Map<String, Object?> get fields => {'passengerId': passengerId};
}

/// Short change landing: the token flashes orange.
final class FlashCue extends TripCue {
  const FlashCue(this.passengerId);

  final String passengerId;

  @override
  Map<String, Object?> get fields => {'passengerId': passengerId};
}

/// A passenger's line, for a bubble and «آخر كلام».
final class LineCue extends TripCue {
  const LineCue({
    required this.passengerId,
    required this.speaker,
    required this.text,
    required this.style,
  });

  final String passengerId;
  final SpeakerLabel speaker;
  final String text;
  final BubbleStyle style;

  @override
  Map<String, Object?> get fields => {
    'passengerId': passengerId,
    'speaker': speaker,
    'text': text,
    'style': style,
  };
}

/// A money line for «آخر كلام».
final class LogCue extends TripCue {
  const LogCue(this.line);

  final LogLine line;

  @override
  Map<String, Object?> get fields => {'line': line};
}

/// The fare-increase banner.
final class BannerCue extends TripCue {
  const BannerCue({required this.oldPiasters, required this.newPiasters});

  final int oldPiasters;
  final int newPiasters;

  @override
  Map<String, Object?> get fields => {
    'oldPiasters': oldPiasters,
    'newPiasters': newPiasters,
  };
}

/// A refused command: a line in the log's place, or a control that shakes
/// (research R22).
final class FeedbackCue extends TripCue {
  const FeedbackCue(this.code);

  final RejectionCode code;

  /// Said in words; the others only shake their control.
  bool get spoken => rejectionSpoken(code);

  @override
  Map<String, Object?> get fields => {'code': code};
}

/// The rejections said in words (contracts/trip-view.md "Rejections").
bool rejectionSpoken(RejectionCode code) => switch (code) {
  RejectionCode.cannotMakeChange ||
  RejectionCode.breakLimit ||
  RejectionCode.boosterLimit ||
  RejectionCode.commandLimit => true,
  _ => false,
};

/// The cues of [events], in event order. [before] is the state the events
/// started from, for what they removed (an arrived token's sender).
List<TripCue> mapCues(
  List<DomainEvent> events, {
  required TripState before,
  required TripState after,
  required TripFacts facts,
  required SpeechResolver speech,
}) {
  final cues = <TripCue>[];
  int amountOf(int tokenId) =>
      (before.token(tokenId) ?? after.token(tokenId))?.pieces.total ?? 0;

  for (final event in events) {
    switch (event) {
      case MoneyArrivedAtDriver(
        :final tokenId,
        :final kind,
        :final amountPiasters,
      ):
        cues
          ..add(const SoundCue(CueSound.coin))
          ..add(const HapticCue(HapticKind.light));
        if (kind == TokenKind.fare) {
          final owner = before.token(tokenId)?.owner;
          cues.add(
            LogCue(
              LogLine(
                kind: LogKind.fareArrived,
                speaker: owner == null ? null : speakerOf(owner, before, facts),
                amountPiasters: amountPiasters,
              ),
            ),
          );
        }
      case ChangeDelivered(:final passengerId, :final result):
        switch (result) {
          case ChangeResult.exact:
            cues.add(const SoundCue(CueSound.thanks));
          case ChangeResult.short:
            cues
              ..add(const SoundCue(CueSound.wrong))
              ..add(FlashCue(passengerId));
          case ChangeResult.over || ChangeResult.notOwed:
          // Silent: «المستغل يسكت». The result lists it.
        }
      case ChangeSent(:final passengerId):
        cues
          ..add(HighlightCue(passengerId))
          ..add(const SoundCue(CueSound.notePass));
      case ExcessReturned():
        cues
          ..add(const SoundCue(CueSound.coin))
          ..add(const HapticCue(HapticKind.light));
      case StationWarning():
        cues.add(const SoundCue(CueSound.call));
      case StationReached():
        cues.add(const SoundCue(CueSound.horn));
      case PassengerAlighted(:final outcome):
        switch (outcome) {
          case AlightOutcome.fight:
            cues
              ..add(const SoundCue(CueSound.fight))
              ..add(const HapticCue(HapticKind.heavy))
              ..add(const ShakeCue());
          case AlightOutcome.missedStop:
            cues.add(const SoundCue(CueSound.wrong));
          default:
        }
      case MoneyDropped(:final tokenId):
        cues
          ..add(const SoundCue(CueSound.bump))
          ..add(const HapticCue(HapticKind.heavy))
          ..add(const ShakeCue())
          ..add(
            LogCue(
              LogLine(kind: LogKind.dropped, amountPiasters: amountOf(tokenId)),
            ),
          );
      case DroppedLost(:final tokenId):
        cues.add(
          LogCue(
            LogLine(kind: LogKind.lost, amountPiasters: amountOf(tokenId)),
          ),
        );
      case FareIncreased(:final amountPiasters):
        final base =
            (before.nextStation ?? before.schedule.lastOrNull)?.farePiasters ??
            0;
        final old = base + before.fareIncreasePiasters;
        cues
          ..add(const SoundCue(CueSound.alert))
          ..add(BannerCue(oldPiasters: old, newPiasters: old + amountPiasters))
          ..add(
            LogCue(
              LogLine(kind: LogKind.fareUp, amountPiasters: amountPiasters),
            ),
          );
      case BreakCompleted(:final denomination):
        cues
          ..add(const SoundCue(CueSound.coin))
          ..add(const HapticCue(HapticKind.light))
          ..add(
            LogCue(
              LogLine(kind: LogKind.breakDone, amountPiasters: denomination),
            ),
          );
      case TripFailed():
        cues
          ..add(const SoundCue(CueSound.fight))
          ..add(const HapticCue(HapticKind.heavy));
      case LiarCaught():
        cues.add(const SoundCue(CueSound.thanks));
      case FalseAccusation():
        cues.add(const SoundCue(CueSound.wrong));
      case PassengerSpeaks(:final passengerId, :final slot):
        final text = speech.lineOf(event);
        if (text != null) {
          cues.add(
            LineCue(
              passengerId: passengerId,
              speaker: speakerOf(passengerId, after, facts),
              text: text,
              style: bubbleStyleOf(slot),
            ),
          );
        }
      default:
    }
  }
  return cues;
}
