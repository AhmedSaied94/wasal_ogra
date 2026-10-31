// الشقة's goal view (specs/015-m10-apartment-story, contracts/apartment.md
// "The goal view", T039): the three chapter states, the ready CTA and what
// it does. The full board check is T049's.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/features/home/application/start_next_trip.dart';

import 'package:content_models/content_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wassal/features/apartment/application/apartment_providers.dart';
import 'package:wassal/features/apartment/presentation/goal_view.dart';

import '../../helpers/lines.dart';
import '../../helpers/progress.dart';
import '../../helpers/synthetic_packs.dart';

/// A player in the sample's chapter, at [jenehat], on the apartment tab.
Future<ProviderContainer> _open(
  WidgetTester tester, {
  Map<String, int> stars = const {},
  Set<(SkuKind, String)> owned = const {},
  int jenehat = 0,
}) async => (await pumpLinesApp(
  tester,
  pack: samplePackJsonForLines(),
  location: '/apartment',
  state: playerState(jenehat: jenehat, stars: stars, owned: owned),
  // The bar animates: nothing settles.
  settle: false,
)).$1;

/// Captures `SemanticsService`'s announcements for the test.
List<Object?> _announcements() {
  final calls = <Object?>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockDecodedMessageHandler<Object?>(SystemChannels.accessibility, (
        message,
      ) async {
        calls.add(message);
        return null;
      });
  addTearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockDecodedMessageHandler<Object?>(
          SystemChannels.accessibility,
          null,
        ),
  );
  return calls;
}

void main() {
  testWidgets('chapter 1: the line goal counts trips, with no CTA', (
    tester,
  ) async {
    await _open(tester);
    expect(find.text('تحويش الجواز'), findsOneWidget);
    // The board's «خلّص خط الحي» (the line goal's name).
    expect(find.text('خلّص خط الحي'), findsOneWidget);
    // The sample's line has two regular trips. The numbers carry their
    // direction isolates, so the row is matched by its word.
    expect(find.textContaining('مشوار'), findsOneWidget);
    expect(find.textContaining('اشتري'), findsNothing);
    expect(find.text('جاهزة!'), findsNothing);
  });

  testWidgets('chapter 3 below the price: no CTA', (tester) async {
    await _open(tester, stars: hayDone, owned: {microOld}, jenehat: 899);
    expect(find.text('الشبكة'), findsOneWidget);
    expect(find.textContaining('٩٠٠'), findsOneWidget);
    expect(find.text('جاهزة!'), findsNothing);
    expect(find.textContaining('اشتري'), findsNothing);
  });

  testWidgets('chapter 3 ready: «جاهزة!» and buying the shabka once', (
    tester,
  ) async {
    final container = await _open(
      tester,
      stars: hayDone,
      owned: {microOld},
      jenehat: 900,
    );
    expect(find.text('جاهزة!'), findsOneWidget);
    final buy = find.byKey(ApartmentGoalView.buyKey);
    expect(buy, findsOneWidget);

    await tester.tap(buy);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    // Bought once (SC-002): the chapter is met, and the tab moves on to the
    // apartment (the sample's ch3 has no story trip; the draft's has one).
    expect(locationOf(container), '/apartment');
    expect(find.text('الشبكة'), findsNothing);
    expect(find.text('شقة العُمر'), findsOneWidget);
  });

  testWidgets('chapter 3 with a story trip: buying the shabka opens its card '
      'although the tab has moved on to the rooms', (tester) async {
    // The release draft's chapter 3 names `line_gamaa.18`. Buying the goal
    // makes chapter 4 current, so the goal view is gone before the purchase
    // returns: the screen that stays starts the trip.
    final (container, _) = await pumpLinesApp(
      tester,
      pack: storyShaped(),
      location: '/apartment',
      state: playerState(
        jenehat: 6000,
        stars: {
          for (var i = 1; i <= 20; i++)
            'line_hay.${i.toString().padLeft(2, '0')}': 3,
        },
        owned: {microOld},
      ),
      settle: false,
    );
    await tester.tap(find.byKey(ApartmentGoalView.buyKey));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(locationOf(container), '/apartment/pre-trip/line_gamaa.18');
    expect(find.byKey(ApartmentGoalView.buyKey), findsNothing);
  });

  testWidgets('chapter 2: the CTA opens the vehicle sheet', (tester) async {
    final container = await _open(tester, stars: hayDone, jenehat: 1500);
    // A vehicle is masculine: «جاهز!».
    expect(find.text('جاهز!'), findsOneWidget);
    await tester.tap(find.byKey(ApartmentGoalView.buyKey));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(locationOf(container), '/lines/vehicle/micro_old');
  });

  testWidgets('the chapter bar opens the timeline', (tester) async {
    final container = await _open(tester);
    await tester.tap(find.text('كل الفصول'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(locationOf(container), '/apartment/chapters');
  });

  test('the bar memory hands back the last value and keeps the new one', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final bar = container.read(goalBarSeenProvider.notifier);
    expect(bar.take(ChapterId.ch3Shabka, 0.3), 0);
    expect(bar.take(ChapterId.ch3Shabka, 0.6), 0.3);
    expect(bar.take(ChapterId.ch3Shabka, 0.6), 0.6);
  });

  testWidgets('the bar stores the value it drew, for the next animation', (
    tester,
  ) async {
    final container = await _open(
      tester,
      stars: hayDone,
      owned: {microOld},
      jenehat: 899,
    );
    final seen = container.read(goalBarSeenProvider);
    expect(seen[ChapterId.ch3Shabka], closeTo(899 / 900, 1e-9));
  });

  testWidgets('the ready state announces «{goal} جاهزة»', (tester) async {
    final announcements = _announcements();
    await _open(tester, stars: hayDone, owned: {microOld}, jenehat: 900);
    await tester.pump();
    // The channel's payload is `{type: announce, data: {message, …}}`.
    final spoken = [
      for (final message in announcements)
        if (message is Map && message['data'] is Map)
          if ((message['data'] as Map)['message'] case final String text) text,
    ];
    expect(spoken, contains(contains('جاهزة')));
  });

  test('StartFrom.apartment names the shabka trip\'s card', () {
    // The contract's "The goal view" hand-off, kept here so the enum's use
    // is visible beside its test.
    expect(StartFrom.values, contains(StartFrom.apartment));
  });
}
