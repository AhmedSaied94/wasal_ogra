// Speech bubbles on the trip clock (contracts/trip-view.md "Speech and
// bubbles"): at most two at once, each for its minimum time, one per
// passenger, the rest waiting their turn.
import 'package:wassal/features/trip/domain/trip_view.dart';
import 'package:wassal/features/trip/domain/view_value.dart';

/// Bubbles on screen at once.
const maxVisibleBubbles = 2;

/// A line waiting for a bubble.
final class WaitingLine extends ViewValue {
  const WaitingLine({
    required this.passengerId,
    required this.text,
    required this.style,
    required this.emittedAtMs,
  });

  final String passengerId;
  final String text;
  final BubbleStyle style;
  final int emittedAtMs;

  @override
  Map<String, Object?> get fields => {
    'passengerId': passengerId,
    'text': text,
    'style': style,
    'emittedAtMs': emittedAtMs,
  };
}

final class BubbleQueue extends ViewValue {
  const BubbleQueue({this.visible = const [], this.waiting = const []});

  static const empty = BubbleQueue();

  final List<BubbleView> visible;
  final List<WaitingLine> waiting;

  /// [line] joins the queue.
  BubbleQueue push(WaitingLine line) =>
      BubbleQueue(visible: visible, waiting: [...waiting, line]);

  /// The queue at [tMs]: bubbles that had their time leave, lines that
  /// waited too long are dropped, and waiting lines fill the room in emit
  /// order, skipping a passenger who already has a bubble. [reserved]
  /// slots are another speaker's (بلية's, specs/012-m07-onboarding/
  /// contracts/coach.md): bubbles already up keep their time, and no new
  /// one takes the room.
  BubbleQueue at(int tMs, {required int bubbleMinMs, int reserved = 0}) {
    final shown = [
      for (final bubble in visible)
        if (tMs - bubble.shownAtMs < bubbleMinMs) bubble,
    ];
    final left = <WaitingLine>[];
    for (final line in waiting) {
      if (tMs - line.emittedAtMs > 2 * bubbleMinMs) continue;
      final speaking = shown.any((b) => b.passengerId == line.passengerId);
      if (shown.length < maxVisibleBubbles - reserved && !speaking) {
        shown.add(
          BubbleView(
            passengerId: line.passengerId,
            text: line.text,
            style: line.style,
            shownAtMs: tMs,
          ),
        );
      } else {
        left.add(line);
      }
    }
    return BubbleQueue(visible: shown, waiting: left);
  }

  /// [passengers] speak now: their latest lines go first and every bubble
  /// on screen makes room, so a dispute shows both accusations at once
  /// while the clock stops. Their earlier waiting lines are dropped.
  BubbleQueue interrupt(Set<String> passengers) {
    final latest = <String, int>{
      for (final (i, line) in waiting.indexed)
        if (passengers.contains(line.passengerId)) line.passengerId: i,
    };
    return BubbleQueue(
      waiting: [
        for (final (i, line) in waiting.indexed)
          if (latest[line.passengerId] == i) line,
        for (final line in waiting)
          if (!passengers.contains(line.passengerId)) line,
      ],
    );
  }

  bool isTalking(String passengerId) =>
      visible.any((b) => b.passengerId == passengerId);

  @override
  Map<String, Object?> get fields => {'visible': visible, 'waiting': waiting};
}
