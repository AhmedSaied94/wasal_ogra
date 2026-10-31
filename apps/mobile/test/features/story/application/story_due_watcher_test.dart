// The goal scenes due (specs/015-m10-apartment-story, contracts/story-flow.md
// "Due", T076): a chapter completed here makes its goal scene due; a room's
// completion, and a completion the base already has, make nothing due.
import 'package:content_models/content_models.dart';
import 'package:flutter/foundation.dart' show FlutterError, FlutterErrorDetails;
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/economy/economy.dart';
import 'package:wassal/features/onboarding/onboarding_providers.dart';
import 'package:wassal/features/story/application/story_due_watcher.dart';

import '../../../helpers/progress.dart';

final class _Flags extends FirstSessionFlagsNotifier {
  final due = <String>[];

  @override
  Future<void> addSceneDue(String sceneId) async => due.add(sceneId);
}

final class _FailingFlags extends FirstSessionFlagsNotifier {
  @override
  Future<void> addSceneDue(String sceneId) =>
      Future.error(Exception('disk full'));
}

EconomyState _state({
  Set<(SkuKind, String)> owned = const {},
  Map<String, int> stars = const {},
}) => EconomyState.newPlayer(fuelMax: 5, nowMs: 0).copyWith(
  ownership: {
    for (final (kind, id) in owned)
      (kind, id): Owned(
        kind: kind,
        acquiredAtMs: 0,
        variantId: kind == SkuKind.item ? 'classic' : null,
      ),
  },
  progress: {
    for (final MapEntry(key: id, value: stars) in stars.entries)
      id: TripProgress(bestStars: stars, plays: 1),
  },
);

EconomyView _view(EconomyState state, {EconomyState? confirmed}) => EconomyView(
  state,
  const FuelView(liters: 5, max: 5, unlimitedUntilMs: null),
  confirmed: ConfirmedState(confirmed ?? state),
);

void main() {
  final content = sampleWith((_) {});

  test('a vehicle bought here makes chapter 2\'s goal scene due', () async {
    final flags = _Flags();
    final watcher = StoryDueWatcher(content, flags);
    // Chapter 1 is already met; buying the microbus meets chapter 2.
    final before = _view(_state(stars: hayDone));
    final after = _view(
      _state(stars: hayDone, owned: {microOld}),
      confirmed: _state(stars: hayDone),
    );
    await watcher.onView(before, after);
    expect(flags.due, ['father_visit']);
  });

  test('a failed write is reported, not left unhandled', () async {
    final flags = _FailingFlags();
    final watcher = StoryDueWatcher(content, flags);
    final before = _view(_state(stars: hayDone));
    final after = _view(
      _state(stars: hayDone, owned: {microOld}),
      confirmed: _state(stars: hayDone),
    );
    final reported = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = reported.add;
    addTearDown(() => FlutterError.onError = previous);
    await watcher.onView(before, after);
    expect(reported.single.exception, isA<Exception>());
    expect(reported.single.library, 'story');
  });

  test('a completion the confirmed base has makes nothing due', () async {
    final flags = _Flags();
    final watcher = StoryDueWatcher(content, flags);
    final before = _view(_state(stars: hayDone));
    final after = _view(_state(stars: hayDone, owned: {microOld}));
    await watcher.onView(before, after);
    expect(flags.due, isEmpty);
  });

  test('a room completion makes nothing due', () async {
    final flags = _Flags();
    final watcher = StoryDueWatcher(content, flags);
    final before = _view(_state(stars: hayDone, owned: {microOld, shabka}));
    final after = _view(
      _state(
        stars: hayDone,
        owned: {
          microOld,
          shabka,
          for (final item in content.itemsOf(RoomId.salon))
            (SkuKind.item, item.itemId),
        },
      ),
      confirmed: _state(stars: hayDone, owned: {microOld, shabka}),
    );
    await watcher.onView(before, after);
    expect(flags.due, isEmpty);
  });
}
