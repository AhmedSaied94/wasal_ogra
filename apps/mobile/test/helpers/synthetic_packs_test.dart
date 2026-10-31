import 'dart:convert';

import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/content/pack_content_source.dart';
import 'package:wassal/core/progress/domain/unlocks.dart';

import 'synthetic_packs.dart';

// The two M10 packs (specs/015-m10-apartment-story, T031): the boards' salon
// and the release draft's story shape. Both decode through the real models,
// so every test that reads them reads a pack the app accepts.

void main() {
  test('artboardSalon: the boards\' salon, chapter 4 current', () {
    final content = PackContentSource(Pack.fromJson(artboardSalon()));

    expect(content.itemsOf(RoomId.salon).map((i) => i.itemId), [
      'salon.nish',
      'salon.sitara',
      'salon.antreeh',
      'salon.nagfa',
    ]);
    // The two prices the rooms board draws, and the bed's shabka.
    expect(content.price(SkuKind.item, 'salon.antreeh')!.amount, 3200);
    expect(content.price(SkuKind.item, 'salon.nagfa')!.amount, 2400);
    expect(content.price(SkuKind.chapter, 'ch3_shabka')!.amount, 6000);
    expect(content.familyRequests, hasLength(3));
    expect(content.chapters, hasLength(7));
    expect(apartmentOpens(content)?.chapterId, ChapterId.ch4Salon);
    // Every item's slot fits its room's 358 x 300 space.
    for (final item in content.itemsOf(RoomId.salon)) {
      final slot = item.slot;
      expect(slot.x + slot.w, lessThanOrEqualTo(358), reason: item.itemId);
      expect(slot.y + slot.h, lessThanOrEqualTo(300), reason: item.itemId);
    }
  });

  test('storyShaped: the draft\'s story with the salon and the_fatha', () {
    final content = PackContentSource(Pack.fromJson(storyShaped()));

    expect(content.chapters.map((c) => c.chapterId), [
      ChapterId.ch1FirstJob,
      ChapterId.ch2HerFather,
      ChapterId.ch3Shabka,
      ChapterId.ch4Salon,
    ]);
    expect(content.itemsOf(RoomId.salon), hasLength(4));
    expect(
      [
        for (final item in content.itemsOf(RoomId.salon))
          content.price(SkuKind.item, item.itemId)!.amount,
      ],
      [750, 1050, 1300, 1600],
    );
    expect(content.familyRequests, hasLength(3));

    // The three story trips, and the scene each chapter's goal opens.
    expect(content.chapter(ChapterId.ch1FirstJob)!.storyTripId, 'line_hay.20');
    expect(
      [
        for (final chapter in content.chapters)
          if (chapter.scenes.any((s) => s.plays == null)) chapter.chapterId,
      ],
      [ChapterId.ch2HerFather, ChapterId.ch4Salon],
    );
    final fatha = content.chapter(ChapterId.ch3Shabka)!.scenes.single;
    expect(
      (fatha.sceneId, fatha.plays?.kind, fatha.plays?.tripId),
      ('the_fatha', ScenePlaysKind.afterTrip, 'line_gamaa.18'),
    );
  });

  test('both packs are strict JSON, as a pack file is', () {
    for (final json in [artboardSalon(), storyShaped()]) {
      final bytes = utf8.encode(jsonEncode(json));
      expect(
        () => Pack.fromJson(
          jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>,
        ),
        returnsNormally,
      );
    }
  });
}
