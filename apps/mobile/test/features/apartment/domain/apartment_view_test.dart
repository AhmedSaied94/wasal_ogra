// M10's apartment tab view (specs/015-m10-apartment-story, data-model
// "Apartment", T036): the goal view before the apartment opens, the rooms
// view from it, and the end of the story.
import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/content/domain/content_source.dart';
import 'package:wassal/core/progress/domain/player_progress.dart';
import 'package:wassal/features/apartment/domain/apartment_view.dart';
import 'package:wassal/features/apartment/domain/goal_view_model.dart';

import '../../../helpers/progress.dart';

/// The sample with chapters 1 to 3 met: the apartment's chapter is current.
PlayerProgress _atSalon({Set<(SkuKind, String)> more = const {}}) =>
    player(hayDone, {microOld, shabka, ...more});

ApartmentView _view(
  ContentSource content,
  PlayerProgress p, {
  int jenehat = 0,
}) => apartmentViewOf(
  content,
  p,
  jenehat: jenehat,
  variantOf: (_) => null,
  requestsClaimed: const {},
  scenesSeen: const {},
  pendingTotal: 0,
);

void main() {
  test('before the apartment opens: the current chapter\'s goal', () {
    final view = _view(sampleWith((_) {}), player());
    expect(view, isA<GoalView>());
    final model = (view as GoalView).model!;
    expect(model.chapter.chapterId, ChapterId.ch1FirstJob);
  });

  test('a pack with no room chapter keeps the goal view', () {
    final content = sampleWith((json) {
      json['chapters'] = [
        for (final chapter in entries(json, 'chapters'))
          if (chapter['chapter_id'] != 'ch4_salon') chapter,
      ];
      json['rooms'] = <Object?>[];
      json['items'] = <Object?>[];
      json['family_requests'] = <Object?>[];
    });
    final view = _view(content, player());
    expect(view, isA<GoalView>());
    // With nothing met, chapter 1 is still the one to save for.
    expect((view as GoalView).model!.chapter.chapterId, ChapterId.ch1FirstJob);
  });

  test('from the apartment\'s chapter on: the current room', () {
    final view = _view(sampleWith((_) {}), _atSalon());
    expect(view, isA<RoomsView>());
    final rooms = view as RoomsView;
    expect(rooms.model.chapter.chapterId, ChapterId.ch4Salon);
    expect(rooms.model.room.roomId, RoomId.salon);
    expect(rooms.storyEnd, isFalse);
  });

  test('the last chapter complete: the end of the story', () {
    // artboardSalon has ch5 to ch7 as purchase goals after the salon.
    final content = artboardSalonContent();
    final p = player(hayDone, {
      microOld,
      shabka,
      for (final item in content.itemsOf(RoomId.salon))
        (SkuKind.item, item.itemId),
      (SkuKind.chapter, 'ch5_kitchen'),
      (SkuKind.chapter, 'ch6_bedroom'),
      (SkuKind.chapter, 'ch7_wedding'),
    });
    final view = _view(content, p);
    expect(view, isA<RoomsView>());
    expect((view as RoomsView).storyEnd, isTrue);
    expect(view.model.room.roomId, RoomId.salon);
  });

  test('a goal view without a chapter has no model', () {
    final content = sampleWith((json) => json['chapters'] = <Object?>[]);
    final view = _view(content, player());
    expect(view, isA<GoalView>());
    expect((view as GoalView).model, isNull);
    expect(
      apartmentViewOf(
        content,
        player(),
        jenehat: 0,
        variantOf: (_) => null,
        requestsClaimed: const {},
        scenesSeen: const {},
        pendingTotal: 0,
      ),
      isA<GoalView>(),
    );
  });

  test('the goal model carries the chapter\'s goal, not a room\'s', () {
    final view = _view(sampleWith((_) {}), player(), jenehat: 400);
    final model = (view as GoalView).model!;
    expect(model, isA<GoalViewModel>());
    expect(model.ready, isFalse);
  });
}
