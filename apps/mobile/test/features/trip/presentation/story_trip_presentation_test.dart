import 'package:content_models/content_models.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/core/l10n/number_formatter.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/trip/domain/looks.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';
import 'package:wassal/features/trip/presentation/overlays/hit_areas.dart';
import 'package:wassal/features/trip/presentation/overlays/rider_labels.dart';
import 'package:wassal/features/trip/presentation/overlays/story_strip.dart';
import 'package:wassal/features/trip/presentation/scene/passenger_art.dart';
import 'package:wassal/features/trip/presentation/scene/svg_passenger_art.dart';
import 'package:wassal/features/trip/presentation/scene/trip_game.dart';
import 'package:wassal/features/trip/presentation/top_bar/top_bar.dart';
import 'package:wassal/core/theme/components/characters.dart';
import 'package:wassal/features/trip/domain/poses.dart';
import 'package:wassal/features/trip/presentation/dashboard/dashboard.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

import '../../../design/samples/c_trip.dart';
import '../../../helpers/trip.dart';

// A story trip on the trip screen (specs/015-m10-apartment-story, contracts/
// story-trip.md "What the screen shows", "Riders in the scene", tasks.md
// T122): the chapter's title under the story chip, the strip's condition
// and states, the rider in its seat, and its comment over the face.

const numbers = NumberFormatter(DigitStyle.arabicIndic);

/// The sample pack's story trip: المعلم rides in `A_l`, on the tuk-tuk.
const _storyTrip = 'line_hay.03';
const _riderSeat = 'A_l';

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(TripDashboard)));

TripGame _game(WidgetTester tester) => tester
    .widget<GameWidget<TripGame>>(find.byType(GameWidget<TripGame>))
    .game!;

Rect _scene(WidgetTester tester) =>
    tester.getRect(find.byType(GameWidget<TripGame>));

/// `C-Trip`'s state with no one aboard, so nothing sits where the story
/// trip's own seats are.
TripView _view({
  StoryStripView? strip,
  String? title,
  RiderBubbleView? rider,
}) => cTripView(
  passengers: const [],
  tokens: const [],
  bubbles: const [],
  log: const [],
  storyStrip: strip,
  storyTitle: title,
  riderBubble: rider,
);

const _says = RiderBubbleView(
  speaker: StoryCharacter.moallem,
  seatId: _riderSeat,
  text: 'الباقي يا أسطى، مش كده',
);

final class _Art implements PassengerArt {
  _Art(this.look, this.row);

  final Look look;
  final SeatRow row;
  final surprises = <bool>[];
  final updates = <PassengerView>[];

  @override
  bool reduceMotion = false;

  @override
  void update(PassengerView view) => updates.add(view);

  @override
  void play(CharacterTrigger trigger) {}

  @override
  void surprise({required bool on}) => surprises.add(on);

  @override
  void advance(double dt) {}

  @override
  void render(Canvas canvas, Rect box) {}

  @override
  void dispose() {}
}

final class _Factory implements PassengerArtFactory {
  final made = <_Art>[];

  @override
  PassengerArt create(
    Look look, {
    SeatRow row = SeatRow.a,
    bool reduceMotion = false,
  }) {
    final art = _Art(look, row);
    made.add(art);
    return art;
  }
}

void main() {
  group('title and strip', () {
    testWidgets('the chapter\'s title under the chip, in the line\'s place', (
      tester,
    ) async {
      await pumpCTrip(tester);
      final l10n = _l10n(tester);
      await showTripView(
        tester,
        _view(strip: const StoryStripView(), title: 'المعلم على خط الحي'),
      );
      expect(find.text(l10n.tripStoryChip), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(TripHud.titleKey)).data,
        'المعلم على خط الحي',
      );
    });

    testWidgets('without a title, M02\'s line and number under the chip', (
      tester,
    ) async {
      await pumpCTrip(tester);
      final l10n = _l10n(tester);
      await showTripView(tester, _view(strip: const StoryStripView()));
      expect(find.text(l10n.tripStoryChip), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(TripHud.titleKey)).data,
        l10n.tripHudTitle('خط الجامعة', numbers.integer(12)),
      );
    });

    testWidgets('a trip that is no story has neither chip nor strip', (
      tester,
    ) async {
      await pumpCTrip(tester);
      final l10n = _l10n(tester);
      await showTripView(tester, _view());
      expect(find.text(l10n.tripStoryChip), findsNothing);
      expect(find.byKey(StoryStrip.iconKey), findsNothing);
    });

    testWidgets('the strip says the chapter\'s condition, kept or broken', (
      tester,
    ) async {
      await pumpCTrip(tester);
      const condition = 'المعلم راكب معاك، خلي بالك من الباقي';
      Color? fill() => tester
          .widgetList<Container>(
            find.descendant(
              of: find.byType(StoryStrip),
              matching: find.byType(Container),
            ),
          )
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .map((d) => d.color)
          .firstOrNull;

      await showTripView(
        tester,
        _view(strip: const StoryStripView(text: condition, broken: false)),
      );
      expect(find.text(condition), findsOneWidget);
      expect(fill(), ColorTokens.dashboardBg);

      await showTripView(
        tester,
        _view(strip: const StoryStripView(text: condition, broken: true)),
      );
      expect(fill(), ColorTokens.danger);
    });

    testWidgets('a condition without a rule never turns red, and M02\'s '
        'line stands without a condition', (tester) async {
      await pumpCTrip(tester);
      final l10n = _l10n(tester);
      await showTripView(tester, _view(strip: const StoryStripView()));
      expect(find.text(l10n.tripStoryNoFights), findsOneWidget);
      final fills = tester
          .widgetList<Container>(
            find.descendant(
              of: find.byType(StoryStrip),
              matching: find.byType(Container),
            ),
          )
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .map((d) => d.color);
      expect(fills, everyElement(ColorTokens.dashboardBg));
    });
  });

  group('riders', () {
    testWidgets('one rider at the chapter\'s seat: no tag, no hit area', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpTrip(tester, tripId: _storyTrip);
      final game = _game(tester);
      final riders = game.stage.riders;
      expect(riders, hasLength(1));
      final rider = riders.single;
      expect(rider.rider.character, StoryCharacter.moallem);
      expect(rider.rider.seat, _riderSeat);

      // Drawn at the seat's face, by the scene's art; the static art
      // without Rive.
      game.stepEngine(stepTime: 0);
      await tester.pump();
      final head = game.layout!.seats[_riderSeat]!.head;
      expect(
        rider.artBox,
        Rect.fromLTWH(head.left, head.top, head.width, head.height),
      );
      expect(rider.art, isA<SvgPassengerArt>());

      // It takes no tap and no drop: a hit area for each passenger and
      // none for the rider.
      final view = controllerOf(tester).view!;
      final seated = view.passengers.where(
        (p) =>
            p.presence == PresenceView.aboard ||
            p.presence == PresenceView.boarding,
      );
      expect(find.byType(DragTarget<HandDrag>), findsNWidgets(seated.length));
      expect(seated.any((p) => p.seatId == _riderSeat), isFalse);

      // Screen readers hear it once.
      final l10n = _l10n(tester);
      final label = l10n.tripRiderA11y(l10n.sceneSpeaker('moallem'));
      expect(find.byKey(RiderLabels.keyOf(_riderSeat)), findsOneWidget);
      expect(find.semantics.byLabel(label), findsOne);
      semantics.dispose();
    });

    testWidgets('a trip that is no story has no rider', (tester) async {
      await pumpTrip(tester, tripId: 'line_hay.01');
      expect(_game(tester).stage.riders, isEmpty);
      expect(find.byType(RiderLabels), findsOneWidget);
      expect(find.byKey(RiderLabels.keyOf(_riderSeat)), findsNothing);
    });

    testWidgets('its look is the character\'s, in its seat\'s row', (
      tester,
    ) async {
      await pumpTrip(tester, tripId: _storyTrip);
      final game = _game(tester);
      final factory = _Factory();
      game
        ..art = factory
        ..stepEngine(stepTime: 0);
      await tester.pump();
      final art = factory.made.singleWhere((a) => a.look.id == 'moallem');
      expect(art.look.rive, CharacterAvatar.looks['moallem']);
      expect(art.look.svg, CharacterAvatar.path('moallem'));
      expect(art.row, game.seats.firstWhere((s) => s.seatId == _riderSeat).row);
      // One calm view, given once: a rider has no state to follow.
      expect(art.updates, hasLength(1));
      expect(art.updates.single.mood, 0);
      expect(art.updates.single.presence, PresenceView.aboard);
    });

    testWidgets('surprised while its comment shows, once', (tester) async {
      await pumpTrip(tester, tripId: _storyTrip);
      final game = _game(tester);
      final factory = _Factory();
      game
        ..art = factory
        ..stepEngine(stepTime: 0);
      await tester.pump();
      final art = factory.made.singleWhere((a) => a.look.id == 'moallem');
      expect(art.surprises, isEmpty);

      await showTripView(tester, _view(rider: _says));
      game.stepEngine(stepTime: 0);
      await tester.pump();
      game.stepEngine(stepTime: 0);
      expect(art.surprises, [true]);

      // Frames while it shows don't fire it again.
      game.stepEngine(stepTime: 0);
      expect(art.surprises, [true]);

      await showTripView(tester, _view());
      game.stepEngine(stepTime: 0);
      expect(art.surprises, [true, false]);
    });
  });

  group('the rider\'s bubble', () {
    testWidgets('over its face, the name over the line, said politely', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpTrip(tester, tripId: _storyTrip);
      final l10n = _l10n(tester);
      await showTripView(tester, _view(rider: _says));

      final bubble = find.byType(SpeechBubble);
      expect(bubble, findsOneWidget);
      final name = l10n.sceneSpeaker('moallem');
      expect(
        find.descendant(of: bubble, matching: find.text(name)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: bubble, matching: find.text(_says.text)),
        findsOneWidget,
      );

      // Its tail's tip over the rider's head, as a passenger's.
      final scene = _scene(tester);
      final seat = _game(tester).layout!.seats[_riderSeat]!;
      expect(
        tester
            .getRect(find.byKey(SpeechBubble.tailKey('rider-$_riderSeat')))
            .bottom,
        closeTo(scene.top + seat.bubbleAnchor.y, 1.5),
      );
      final rect = tester.getRect(bubble);
      expect(rect.left, greaterThanOrEqualTo(scene.left + 10 - 0.5));
      expect(rect.right, lessThanOrEqualTo(scene.right - 10 + 0.5));

      final said = l10n.tripRiderSays(name, _says.text);
      expect(
        find.semantics.byPredicate(
          (n) =>
              n.getSemanticsData().flagsCollection.isLiveRegion &&
              n.label == said,
        ),
        findsOne,
      );
      semantics.dispose();
    });

    testWidgets('gone with the comment', (tester) async {
      await pumpTrip(tester, tripId: _storyTrip);
      await showTripView(tester, _view(rider: _says));
      expect(find.byType(SpeechBubble), findsOneWidget);
      await showTripView(tester, _view());
      expect(find.byType(SpeechBubble), findsNothing);
    });
  });
}
