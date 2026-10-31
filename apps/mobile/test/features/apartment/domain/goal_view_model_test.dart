// M10's goal view model (specs/015-m10-apartment-story, contracts/
// apartment.md "The goal view", T037): the three goal kinds over M08's
// savings target, the ready state, the line and the CTA each kind takes.
import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/art/apartment_art.dart';
import 'package:wassal/core/progress/domain/unlocks.dart';
import 'package:wassal/features/apartment/domain/goal_view_model.dart';
import 'package:wassal/features/home/domain/savings_target.dart';

import '../../../helpers/progress.dart';

GoalViewModel _view({
  Map<String, int> stars = const {},
  Set<(SkuKind, String)> owned = const {},
  int jenehat = 0,
}) {
  final content = sampleWith((_) {});
  final p = player(stars, owned);
  final chapter = currentChapter(content, p)!;
  final target = savingsTarget(content, p, jenehat);
  return goalViewModel(content, p, chapter, target as ChapterGoalTarget)!;
}

void main() {
  test('a line goal counts trips, is never ready, and has no action', () {
    final view = _view();
    expect(view.chapter.chapterId, ChapterId.ch1FirstJob);
    expect(view.target.progress, isA<Count>());
    expect(view.ready, isFalse);
    expect(view.action, const NoAction());
    // The author's goal art wins over the kind's fallback.
    expect(view.art, const DrawnGoal('goal_shabka'));
    expect(ApartmentArt.goal('goal_shabka'), isNotNull);
    expect(view.fallbackArt, const TuktukGoal());
    expect(view.line?.speaker, StoryCharacter.moallem);
  });

  test('a vehicle goal is an amount, and its CTA is the vehicle sheet', () {
    final view = _view(stars: hayDone, jenehat: 1000);
    expect(view.chapter.chapterId, ChapterId.ch2HerFather);
    expect(view.target.progress, const Amount(have: 1000, of: 1500));
    expect(view.art, const VehicleGoal(VehicleId.microOld));
    expect(
      view.action,
      const OpenVehicleSheet(VehicleId.microOld, price: 1500),
    );
    expect(view.ready, isFalse);
  });

  test('a vehicle goal is ready when it is affordable and not owned', () {
    expect(_view(stars: hayDone, jenehat: 1500).ready, isTrue);
    expect(_view(stars: hayDone, jenehat: 1499).ready, isFalse);
    // Owned: the chapter is met, so it isn't current any more.
    final owned = _view(stars: hayDone, owned: {microOld}, jenehat: 1500);
    expect(owned.chapter.chapterId, ChapterId.ch3Shabka);
  });

  test('a purchase goal is a buyChapter price, ready at the price', () {
    final short = _view(stars: hayDone, owned: {microOld}, jenehat: 899);
    expect(short.chapter.chapterId, ChapterId.ch3Shabka);
    expect(short.target.progress, const Amount(have: 899, of: 900));
    expect(short.action, const BuyChapter(900));
    expect(short.ready, isFalse);

    final ready = _view(stars: hayDone, owned: {microOld}, jenehat: 900);
    expect(ready.ready, isTrue);
    // The goal's own art still wins over the ring fallback.
    expect(ready.art, const DrawnGoal('goal_shabka'));
    expect(ready.fallbackArt, const RingGoal());
  });

  test('ready_line replaces the goal line only when ready', () {
    final short = _view(stars: hayDone, jenehat: 1400);
    expect(short.line!.text.arEg, contains('ميكروباص'));
    final ready = _view(stars: hayDone, jenehat: 1500);
    expect(ready.line!.speaker, short.line!.speaker);
    expect(ready.line!.text.arEg, contains('جاهز'));
  });

  test('a chapter with no goal art falls back by kind', () {
    final content = sampleWith((json) {
      entry(json, 'chapters', 'chapter_id', 'ch3_shabka').remove('goal_art');
    });
    final p = player(hayDone, {microOld});
    final chapter = currentChapter(content, p)!;
    final view = goalViewModel(
      content,
      p,
      chapter,
      savingsTarget(content, p, 0) as ChapterGoalTarget,
    );
    expect(view!.art, const RingGoal());
    expect(view.fallbackArt, const RingGoal());
  });

  test('no chapters: no goal card', () {
    final content = sampleWith((json) => json['chapters'] = <Object?>[]);
    expect(goalViewModelOf(content, player(), 0), isNull);
  });
}
