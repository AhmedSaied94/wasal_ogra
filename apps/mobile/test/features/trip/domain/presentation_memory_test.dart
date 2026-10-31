// The character slot (specs/015-m10-apartment-story, contracts/story-trip.md
// "Timing", T120): a rider's comment and بلية's bubble share one reserved
// slot. A comment takes it when free, بلية wins a tie, a comment that waited
// past `bubbleMinMs` is dropped, a shown one stays its minimum, and with the
// passengers' bubbles there are never more than two.
import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/features/trip/domain/bubble_queue.dart';
import 'package:wassal/features/trip/domain/presentation_memory.dart';
import 'package:wassal/features/trip/domain/rider_comments.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';

const _minMs = 4000;

const _comment = RiderComment(
  speaker: StoryCharacter.moallem,
  line: 'يا أسطى الفكة',
  ordinal: 0,
);

const _hint = HintView(key: 'tripHintOwed', targetPassengerId: 'a');
const _wish = (source: 'tripHintOwed', line: _hint);

/// A memory with a comment emitted at [at].
PresentationMemory _withComment({int at = 0, PresentationMemory? base}) =>
    (base ?? PresentationMemory.empty).update(
      const [],
      const [],
      tMs: at,
      bubbleMinMs: _minMs,
      riderComments: const [_comment],
    );

BubbleView _bubble(String id, {int at = 0}) => BubbleView(
  passengerId: id,
  text: id,
  style: BubbleStyle.plain,
  shownAtMs: at,
);

void main() {
  test('a comment takes the character slot', () {
    final memory = _withComment().characterAt(
      null,
      tMs: 0,
      bubbleMinMs: _minMs,
    );
    final bubble = memory.character!;
    expect(bubble.speaker, StoryCharacter.moallem);
    expect(bubble.line, const RiderLine('يا أسطى الفكة'));
    expect(bubble.shownAtMs, 0);
    expect(memory.waitingComment, isNull, reason: 'it was taken');
  });

  test('comments are counted for the next one\'s ordinal', () {
    expect(PresentationMemory.empty.riderOrdinal, 0);
    expect(_withComment().riderOrdinal, 1);
    final two = PresentationMemory.empty.update(
      const [],
      const [],
      tMs: 0,
      bubbleMinMs: _minMs,
      riderComments: const [
        _comment,
        RiderComment(speaker: StoryCharacter.moallem, line: 'تاني', ordinal: 1),
      ],
    );
    expect(two.riderOrdinal, 2);
    expect(
      two.waitingComment?.comment.ordinal,
      1,
      reason: 'comments never pile up: the latest waits',
    );
  });

  test('بلية wins a tie, and the comment waits behind him', () {
    final memory = _withComment().characterAt(
      _wish,
      tMs: 0,
      bubbleMinMs: _minMs,
    );
    expect(memory.character?.speaker, StoryCharacter.belya);
    expect(memory.character?.line, _hint);
    expect(memory.waitingComment, isNotNull);
  });

  test('a comment that waited past its minimum is dropped', () {
    var memory = _withComment().characterAt(_wish, tMs: 0, bubbleMinMs: _minMs);
    // بلية's bubble ends at 4000, and the comment is by then past its wait.
    memory = memory.characterAt(null, tMs: _minMs + 1, bubbleMinMs: _minMs);
    expect(memory.character, isNull);
    expect(memory.waitingComment, isNull);
  });

  test('a comment waiting for a free slot is shown while it is fresh', () {
    // Two passengers talking: no room, the comment waits.
    var memory = PresentationMemory(
      bubbles: BubbleQueue(visible: [_bubble('a'), _bubble('b')]),
    );
    memory = _withComment(
      at: 100,
      base: memory,
    ).characterAt(null, tMs: 100, bubbleMinMs: _minMs);
    expect(memory.character, isNull);
    expect(memory.waitingComment, isNotNull);
    // One has left, within the comment's wait.
    memory = PresentationMemory(
      bubbles: BubbleQueue(visible: [_bubble('a')]),
      waitingComment: memory.waitingComment,
      riderOrdinal: memory.riderOrdinal,
    ).characterAt(null, tMs: 1000, bubbleMinMs: _minMs);
    expect(memory.character?.speaker, StoryCharacter.moallem);
  });

  test('it stays its minimum time, and no longer', () {
    var memory = _withComment().characterAt(null, tMs: 0, bubbleMinMs: _minMs);
    memory = memory.characterAt(null, tMs: _minMs - 1, bubbleMinMs: _minMs);
    expect(memory.character, isNotNull);
    memory = memory.characterAt(null, tMs: _minMs, bubbleMinMs: _minMs);
    expect(memory.character, isNull);
  });

  test('a comment up keeps its time when بلية wishes', () {
    var memory = _withComment().characterAt(null, tMs: 0, bubbleMinMs: _minMs);
    memory = memory.characterAt(_wish, tMs: 1000, bubbleMinMs: _minMs);
    expect(memory.character?.speaker, StoryCharacter.moallem);
    memory = memory.characterAt(_wish, tMs: _minMs, bubbleMinMs: _minMs);
    expect(memory.character?.speaker, StoryCharacter.belya);
  });

  test('never more than two bubbles in all (constitution XI)', () {
    var memory = _withComment().characterAt(null, tMs: 0, bubbleMinMs: _minMs);
    // Three passengers want to speak while the rider does.
    for (final id in ['a', 'b', 'c']) {
      memory = PresentationMemory(
        bubbles: memory.bubbles.push(
          WaitingLine(
            passengerId: id,
            text: id,
            style: BubbleStyle.plain,
            emittedAtMs: 0,
          ),
        ),
        character: memory.character,
      );
    }
    memory = memory.at(33, bubbleMinMs: _minMs);
    expect(
      memory.bubbles.visible.length + (memory.character == null ? 0 : 1),
      lessThanOrEqualTo(maxVisibleBubbles),
    );
    expect(memory.bubbles.visible, hasLength(1));
  });
}
