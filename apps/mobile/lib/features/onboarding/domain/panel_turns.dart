// A comic panel's spoken lines as turns (specs/012.5-m22-animated-scenes,
// data-model.md "Turns", contracts/scene-turns.md "The schedule"): when each
// speaker talks, measured from the panel's arrival. Pure Dart: the timings
// come in as arguments.
import 'package:characters/characters.dart';
import 'package:content_models/content_models.dart';

/// How long turns last: [leadIn] before the first, [perLetter] of a line
/// within [min] and [max], and [pause] between two.
final class TurnTimings {
  TurnTimings({
    required this.leadIn,
    required this.perLetter,
    required this.min,
    required this.max,
    required this.pause,
  }) {
    if ([leadIn, perLetter, min, max, pause].any((d) => d.isNegative)) {
      throw ArgumentError('a turn timing is negative');
    }
    if (min > max) {
      throw ArgumentError.value(min, 'min', 'is longer than max ($max)');
    }
  }

  final Duration leadIn;
  final Duration perLetter;
  final Duration min;
  final Duration max;
  final Duration pause;
}

/// One spoken line's turn: its [index] among the panel's spoken lines, its
/// [speaker], and when it [start]s and [end]s.
final class Turn {
  const Turn({
    required this.index,
    required this.speaker,
    required this.start,
    required this.end,
  });

  final int index;
  final String speaker;
  final Duration start;
  final Duration end;
}

/// Where a panel's turns are at a moment: how many have [shown] their
/// bubble, who is [talking] (nobody before the first, in a pause or after
/// the last), and whether the last has started, which decides what «يلا»
/// does.
final class TurnsAt {
  const TurnsAt({
    required this.shown,
    required this.talking,
    required this.lastStarted,
  });

  final int shown;
  final String? talking;
  final bool lastStarted;

  @override
  bool operator ==(Object other) =>
      other is TurnsAt &&
      other.shown == shown &&
      other.talking == talking &&
      other.lastStarted == lastStarted;

  @override
  int get hashCode => Object.hash(shown, talking, lastStarted);

  @override
  String toString() =>
      'TurnsAt(shown: $shown, talking: $talking, lastStarted: $lastStarted)';
}

/// A panel's [turns]: one per line whose speaker isn't [narrator], in order.
final class PanelTurns {
  factory PanelTurns(List<PanelLine> lines, TurnTimings timings) {
    final turns = <Turn>[];
    var start = timings.leadIn;
    for (final line in lines) {
      if (line.speaker == narrator) continue;
      final end = start + _length(line.text.arEg, timings);
      turns.add(
        Turn(
          index: turns.length,
          speaker: line.speaker,
          start: start,
          end: end,
        ),
      );
      start = end + timings.pause;
    }
    return PanelTurns._(List.unmodifiable(turns));
  }

  const PanelTurns._(this.turns);

  /// The speaker of a caption, which takes no turn.
  static const narrator = 'narrator';

  final List<Turn> turns;

  /// When the last turn ends; zero without one.
  Duration get end => turns.isEmpty ? Duration.zero : turns.last.end;

  /// The turns at [elapsed] since the panel arrived.
  TurnsAt at(Duration elapsed) {
    var shown = 0;
    String? talking;
    for (final turn in turns) {
      if (turn.start > elapsed) break;
      shown++;
      if (elapsed < turn.end) talking = turn.speaker;
    }
    return TurnsAt(
      shown: shown,
      talking: talking,
      lastStarted: turns.isEmpty || elapsed >= turns.last.start,
    );
  }

  /// [perLetter] for each letter of [text], within [min] and [max]. A letter
  /// is a grapheme cluster that isn't white space, so a vowel mark counts
  /// with its letter.
  static Duration _length(String text, TurnTimings timings) {
    final letters = text.characters.where((c) => c.trim().isNotEmpty).length;
    final length = timings.perLetter * letters;
    if (length < timings.min) return timings.min;
    if (length > timings.max) return timings.max;
    return length;
  }
}
