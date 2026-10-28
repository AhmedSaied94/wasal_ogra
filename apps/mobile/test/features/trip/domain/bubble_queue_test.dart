import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/features/trip/domain/bubble_queue.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';

const minMs = 4000;

WaitingLine line(String passenger, String text, int at) => WaitingLine(
  passengerId: passenger,
  text: text,
  style: BubbleStyle.plain,
  emittedAtMs: at,
);

List<String> texts(BubbleQueue q) => [for (final b in q.visible) b.text];

void main() {
  test('at most two visible; the rest wait in order', () {
    var q = BubbleQueue.empty
        .push(line('a', '1', 0))
        .push(line('b', '2', 0))
        .push(line('c', '3', 0))
        .at(0, bubbleMinMs: minMs);
    expect(texts(q), ['1', '2']);
    expect(q.waiting.map((w) => w.text), ['3']);
    q = q.at(minMs - 33, bubbleMinMs: minMs);
    expect(texts(q), ['1', '2'], reason: 'each stays its minimum');
    q = q.at(minMs, bubbleMinMs: minMs);
    expect(texts(q), ['3']);
    expect(q.visible.single.shownAtMs, minMs);
  });

  test('a passenger has one bubble at a time', () {
    var q = BubbleQueue.empty
        .push(line('a', '1', 0))
        .push(line('a', '2', 0))
        .push(line('b', '3', 0))
        .at(0, bubbleMinMs: minMs);
    expect(texts(q), ['1', '3']);
    q = q.at(minMs, bubbleMinMs: minMs);
    expect(texts(q), ['2']);
  });

  test('a line that waited more than twice the minimum is dropped', () {
    var q = BubbleQueue.empty
        .push(line('a', '1', 0))
        .push(line('b', '2', 0))
        .push(line('c', 'late', 0))
        .at(0, bubbleMinMs: minMs);
    // The two visible ones keep the room past the late line's limit.
    q = BubbleQueue(
      visible: [
        for (final b in q.visible)
          BubbleView(
            passengerId: b.passengerId,
            text: b.text,
            style: b.style,
            shownAtMs: 2 * minMs,
          ),
      ],
      waiting: q.waiting,
    ).at(2 * minMs + 33, bubbleMinMs: minMs);
    expect(q.waiting, isEmpty);
    expect(texts(q), isNot(contains('late')));
  });

  test('a dispute shows both accusations at once', () {
    var q = BubbleQueue.empty
        .push(line('a', 'paying', 0))
        .push(line('c', 'chat', 0))
        .push(line('b', 'early', 0))
        .at(0, bubbleMinMs: minMs);
    expect(texts(q), ['paying', 'chat']);
    q = q
        .push(line('c', 'more chat', 33))
        .push(line('a', 'I paid', 33))
        .push(line('b', 'he did not', 33))
        .interrupt({'a', 'b'})
        .at(33, bubbleMinMs: minMs);
    expect(texts(q), ['I paid', 'he did not']);
    // Only their latest lines: «early» was said before the dispute.
    expect(q.waiting.map((w) => w.text), ['more chat']);
  });

  test('a paused clock freezes everything', () {
    final q = BubbleQueue.empty
        .push(line('a', '1', 0))
        .at(0, bubbleMinMs: minMs);
    expect(q.at(0, bubbleMinMs: minMs), q);
    expect(q.isTalking('a'), isTrue);
    expect(q.isTalking('b'), isFalse);
  });

  group("reserved: بلية's bubble takes a slot (specs/012-m07-onboarding)", () {
    test('with one reserved, at most one rider bubble shows', () {
      var q = BubbleQueue.empty
          .push(line('a', '1', 0))
          .push(line('b', '2', 0))
          .at(0, bubbleMinMs: minMs, reserved: 1);
      expect(texts(q), ['1']);
      expect(q.waiting.map((w) => w.text), ['2']);
      q = q.at(minMs, bubbleMinMs: minMs, reserved: 1);
      expect(texts(q), ['2']);
    });

    test('a bubble already up stays its time when a slot is reserved', () {
      var q = BubbleQueue.empty
          .push(line('a', '1', 0))
          .push(line('b', '2', 0))
          .at(0, bubbleMinMs: minMs);
      q = q.at(33, bubbleMinMs: minMs, reserved: 1);
      expect(texts(q), ['1', '2']);
    });

    test('none reserved is the M02 queue', () {
      final lines = BubbleQueue.empty
          .push(line('a', '1', 0))
          .push(line('b', '2', 0))
          .push(line('c', '3', 0));
      expect(
        lines.at(0, bubbleMinMs: minMs, reserved: 0),
        lines.at(0, bubbleMinMs: minMs),
      );
    });
  });
}
