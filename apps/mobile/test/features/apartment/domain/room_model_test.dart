// M10's rooms model (specs/015-m10-apartment-story, data-model "Apartment",
// T051): the tabs, the pieces by order, the goal scene and the counts.
import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/progress/domain/player_progress.dart';
import 'package:wassal/core/progress/domain/story.dart';
import 'package:wassal/core/progress/domain/unlocks.dart';
import 'package:wassal/features/apartment/domain/room_model.dart';

import '../../../helpers/progress.dart';

const _nish = (SkuKind.item, 'salon.nish');
const _sitara = (SkuKind.item, 'salon.sitara');
const _antreeh = (SkuKind.item, 'salon.antreeh');
const _nagfa = (SkuKind.item, 'salon.nagfa');

/// The artboards' salon, chapter 4 current, with [owned] and [styles].
RoomModel _room({
  Set<(SkuKind, String)> owned = const {},
  Map<String, String> styles = const {},
  int jenehat = 0,
  Set<String> claimed = const {},
  Map<String, Set<String>> seen = const {},
  int pendingTotal = 0,
  PlayerProgress? progress,
}) {
  final content = artboardSalonContent();
  final p = progress ?? player(hayDone, {microOld, shabka, ...owned});
  final chapter = currentChapter(content, p)!;
  return roomModel(
    content,
    p,
    chapter,
    jenehat: jenehat,
    variantOf: (itemId) => styles[itemId],
    requestsClaimed: claimed,
    scenesSeen: seen,
    pendingTotal: pendingTotal,
  )!;
}

void main() {
  test('tabs: the pack\'s rooms by the glossary order, the rest locked', () {
    final model = _room();
    expect(model.tabs.map((t) => t.roomId), [
      RoomId.salon,
      RoomId.kitchen,
      RoomId.bedroom,
    ]);
    expect(model.tabs[0], isA<SelectableTab>());
    expect(model.tabs[1], isA<LockedTab>());
    expect(model.tabs[2], isA<LockedTab>());
  });

  test('tabs: a room whose chapter is locked is a locked tab', () {
    final content = artboardSalonContent();
    final p = player();
    final model = roomModel(
      content,
      p,
      content.chapter(ChapterId.ch4Salon)!,
      jenehat: 0,
      variantOf: (_) => null,
      requestsClaimed: const {},
      scenesSeen: const {},
      pendingTotal: 0,
    )!;
    expect(model.tabs.first, isA<LockedTab>());
  });

  test('cells: owned with its style, the next target, then the rest', () {
    final model = _room(
      owned: {_nish, _sitara},
      styles: {'salon.nish': 'crystal', 'salon.sitara': 'red'},
      jenehat: 1325,
    );
    expect(model.pieces.map((c) => c.item.itemId), [
      'salon.nish',
      'salon.sitara',
      'salon.antreeh',
      'salon.nagfa',
    ]);
    final owned = model.pieces.whereType<OwnedCell>().toList();
    expect(owned.map((c) => c.variantId), ['crystal', 'red']);
    final next = model.pieces[2] as NextTargetCell;
    expect((next.price, next.shortfall, next.affordable), (3200, 1875, false));
    expect(next.progress.fraction, closeTo(1325 / 3200, 1e-9));
    final missing = model.pieces[3] as MissingCell;
    expect(missing.price, 2400);
    expect((model.owned, model.total), (2, 4));
  });

  test('the next target is affordable when the balance covers it', () {
    final model = _room(owned: {_nish, _sitara}, jenehat: 3200);
    final next = model.pieces[2] as NextTargetCell;
    expect((next.shortfall, next.affordable), (0, true));
  });

  test('a style the pack dropped draws the first', () {
    final model = _room(owned: {_nish}, styles: {'salon.nish': 'gone'});
    expect((model.pieces.first as OwnedCell).variantId, 'classic');
  });

  test('the goal scene waits once the room is complete', () {
    final locked = _room(owned: {_nish});
    expect(locked.goalScene!.sceneId, 'family_visit');
    expect(locked.goalSceneState, SceneState.locked);

    final waiting = _room(
      owned: {_nish, _sitara, _antreeh, _nagfa},
      jenehat: 0,
    );
    expect(waiting.complete, isTrue);
    expect(waiting.goalSceneState, SceneState.waiting);

    final seen = _room(
      owned: {_nish, _sitara, _antreeh, _nagfa},
      seen: const {
        'ch4_salon': {'family_visit'},
      },
    );
    expect(seen.goalSceneState, SceneState.seen);
  });

  test('the requests count is open plus done', () {
    expect(_room().requestCount, 3);
    // The red ستاير is done, the كريستال نيش still open.
    expect(
      _room(owned: {_sitara}, styles: {'salon.sitara': 'red'}).requestCount,
      3,
    );
    // The plain ستاير misses its request: it leaves the count.
    expect(
      _room(owned: {_sitara}, styles: {'salon.sitara': 'plain'}).requestCount,
      2,
    );
    expect(_room(claimed: const {'req_sitara_red'}).requestCount, 2);
  });

  test('the pending total passes through', () {
    expect(_room(pendingTotal: 35).pendingTotal, 35);
  });
}
