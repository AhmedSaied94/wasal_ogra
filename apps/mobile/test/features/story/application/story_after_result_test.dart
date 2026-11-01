// The scene after a story trip (specs/015-m10-apartment-story, contracts/
// story-flow.md "Where scenes play", T077): a waiting scene plays and is
// awaited; a scene seen, a trip with none and a trip not finished return at
// once.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/progress/domain/player_progress.dart';
import 'package:wassal/features/story/application/story_after_result.dart';

import '../../../helpers/progress.dart';

void main() {
  final content = sampleWith((_) {});

  StoryAfterResultImpl impl({
    required PlayerProgress progress,
    Map<String, Set<String>> seen = const {},
    required Future<void> Function(String location) push,
  }) => StoryAfterResultImpl(
    content: () => content,
    progress: () => progress,
    seen: () => seen,
    push: push,
  );

  test('plays a waiting after-trip scene and awaits its pop', () async {
    final pushed = <String>[];
    final popped = Completer<void>();
    final after = impl(
      progress: player({'line_hay.03': 1}),
      push: (location) {
        pushed.add(location);
        return popped.future;
      },
    );
    var done = false;
    final running = after.after('line_hay.03').then((_) => done = true);
    await Future<void>.delayed(Duration.zero);
    expect(pushed, ['/story/scene/the_stand']);
    expect(done, isFalse);

    popped.complete();
    await running;
    expect(done, isTrue);
  });

  test('returns at once for a scene already seen', () async {
    final pushed = <String>[];
    await impl(
      progress: player({'line_hay.03': 1}),
      seen: const {
        'ch1_first_job': {'the_stand'},
      },
      push: (location) async => pushed.add(location),
    ).after('line_hay.03');
    expect(pushed, isEmpty);
  });

  test('returns at once for a trip with no scene', () async {
    final pushed = <String>[];
    await impl(
      progress: player({'line_hay.01': 3}),
      push: (location) async => pushed.add(location),
    ).after('line_hay.01');
    expect(pushed, isEmpty);
  });

  test('returns at once for a trip that was not finished', () async {
    final pushed = <String>[];
    await impl(
      progress: player(),
      push: (location) async => pushed.add(location),
    ).after('line_hay.03');
    expect(pushed, isEmpty);
  });
}
