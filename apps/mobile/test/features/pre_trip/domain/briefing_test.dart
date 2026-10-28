// What the pre-trip card says of a trip (specs/013-m08-home-result,
// data-model `TripBriefing`, research R5, R7).
import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/content/domain/content_source.dart';
import 'package:wassal/features/pre_trip/domain/briefing.dart';
import 'package:wassal/features/pre_trip/domain/met_set.dart';
import 'package:wassal/features/trip/domain/looks.dart';

import '../../../helpers/economy.dart';
import '../../../helpers/progress.dart';

const _none = (archetypes: <Archetype>{}, events: <EventId>{});

TripBriefing _brief(
  ContentSource c,
  String tripId, {
  Map<String, int> stars = const {},
  Map<BoosterId, int> inventory = const {},
  MetSet met = _none,
  bool boostersLocked = false,
}) => tripBriefing(
  c,
  tripId: tripId,
  progress: player(stars),
  inventory: inventory,
  met: met,
  boostersLocked: boostersLocked,
)!;

void main() {
  final c = sampleContent();

  test('the header: the line, the trip number, the story chip', () {
    final b = _brief(c, 'line_hay.03');
    expect(b.tripId, 'line_hay.03');
    expect(b.lineName, 'خط الحي');
    expect(b.tripIndex, 3);
    expect(b.isStory, isTrue);
    expect(b.storyRuleNoFights, isTrue);
    final regular = _brief(c, 'line_gamaa.02');
    expect(regular.isStory, isFalse);
    expect(regular.storyRuleNoFights, isFalse);
  });

  test('a trip the pack lacks has no briefing', () {
    expect(
      tripBriefing(
        c,
        tripId: 'line_hay.99',
        progress: player(),
        inventory: const {},
        met: _none,
        boostersLocked: false,
      ),
      isNull,
    );
  });

  group('stops', () {
    test('in drop-off order, slots 1 to 3, with names and fares', () {
      final b = _brief(c, 'line_gamaa.02');
      expect(b.stops, const [
        StopPrice(slot: 1, stationName: 'الكوبري', farePiasters: 450),
        StopPrice(slot: 2, stationName: 'المستشفى', farePiasters: 700),
        StopPrice(slot: 3, stationName: 'الجامعة', farePiasters: 900),
      ]);
    });

    test('by `at_seconds`, whatever order they are written in; four stops', () {
      final shuffled = sampleWith((json) {
        entry(json, 'trips', 'trip_id', 'line_gamaa.02')['stations'] = [
          {'station_id': 'sour', 'at_seconds': 130, 'fare_piasters': 1100},
          {'station_id': 'gamaa', 'at_seconds': 100, 'fare_piasters': 900},
          {'station_id': 'kobri', 'at_seconds': 38, 'fare_piasters': 450},
          {'station_id': 'mostashfa', 'at_seconds': 70, 'fare_piasters': 700},
        ];
      });
      final b = _brief(shuffled, 'line_gamaa.02');
      expect(
        [for (final s in b.stops) s.stationName],
        ['الكوبري', 'المستشفى', 'الجامعة', 'السور'],
      );
      expect([for (final s in b.stops) s.slot], [1, 2, 3, 4]);
    });
  });

  group('rule lines', () {
    test('the student line, when a student rides at a discount', () {
      expect(_brief(c, 'line_hay.01').ruleLines, const [StudentLine(50)]);
    });

    test("another percentage is the trip's", () {
      final thirty = sampleWith((json) {
        (entry(json, 'trips', 'trip_id', 'line_hay.01')['rules']!
                as Map<String, Object?>)['student_discount_pct'] =
            30;
      });
      expect(_brief(thirty, 'line_hay.01').ruleLines, const [StudentLine(30)]);
    });

    test('no line without a discount, or without a student', () {
      // line_gamaa.01 has a student at no discount.
      expect(_brief(c, 'line_gamaa.01').ruleLines, isEmpty);
      // line_hay.03's student-looking rider is a `regular`.
      final discounted = sampleWith((json) {
        (entry(json, 'trips', 'trip_id', 'line_hay.03')['rules']!
                as Map<String, Object?>)['student_discount_pct'] =
            50;
      });
      expect(_brief(discounted, 'line_hay.03').ruleLines, isEmpty);
    });

    test('no bag or child line while no engine archetype carries one', () {
      final authored = sampleWith((json) {
        (entry(json, 'trips', 'trip_id', 'line_gamaa.02')['rules']!
                as Map<String, Object?>)['bag_fare_piasters'] =
            200;
      });
      expect(_brief(authored, 'line_gamaa.02').ruleLines, isEmpty);
    });
  });

  group('the new subject', () {
    test('the first passenger type not met, in definition order', () {
      final b = _brief(c, 'line_gamaa.02');
      expect(b.newSubject, isA<NewArchetype>());
      final subject = b.newSubject! as NewArchetype;
      expect(subject.archetype, Archetype.honest);
      // The look of the trip's first passenger of that type.
      expect(subject.look, lookFor('effendi_suit', Archetype.honest));
    });

    test('met ones are skipped; `regular` is never new', () {
      final met = (
        archetypes: {Archetype.honest, Archetype.hurry},
        events: <EventId>{},
      );
      final b = _brief(c, 'line_gamaa.02', met: met);
      expect((b.newSubject! as NewArchetype).archetype, Archetype.groupPayer);
      final hay = _brief(
        c,
        'line_hay.03',
        met: (archetypes: {Archetype.chatty}, events: <EventId>{}),
      );
      expect(hay.newSubject, isNull);
    });

    test('then the events, in definition order', () {
      final met = (
        archetypes: {Archetype.groupPayer, Archetype.hajja},
        events: {EventId.traffic},
      );
      final b = _brief(c, 'line_hay.02', met: met);
      expect(b.newSubject, isA<NewEvent>());
      final event = b.newSubject! as NewEvent;
      expect(event.eventId, EventId.paymentDispute);
      expect(event.icon, 'speech');
    });

    test('nothing new once all is met', () {
      final met = (
        archetypes: {Archetype.groupPayer, Archetype.hajja},
        events: {EventId.traffic, EventId.paymentDispute},
      );
      expect(_brief(c, 'line_hay.02', met: met).newSubject, isNull);
    });
  });

  test('the stars earned are the best stars', () {
    expect(_brief(c, 'line_hay.01').starsEarned, 0);
    expect(_brief(c, 'line_hay.01', stars: {'line_hay.01': 2}).starsEarned, 2);
  });

  group('boosters', () {
    test("the four, in the artboard's order, with their counts", () {
      final b = _brief(
        c,
        'line_hay.01',
        inventory: {BoosterId.ledgerPeek: 1, BoosterId.trafficJam: 2},
      );
      expect(b.boosters, const [
        BoosterTile(booster: BoosterId.changeBag, count: 0),
        BoosterTile(booster: BoosterId.ledgerPeek, count: 1),
        BoosterTile(booster: BoosterId.wakeAll, count: 0),
        BoosterTile(booster: BoosterId.trafficJam, count: 2),
      ]);
      expect(b.boostersHidden, isFalse);
    });

    test('the offer: the first at 0, at its catalog price', () {
      final b = _brief(
        c,
        'line_hay.01',
        inventory: {BoosterId.changeBag: 1, BoosterId.ledgerPeek: 1},
      );
      expect(
        b.buyOffer,
        const BuyOffer(booster: BoosterId.wakeAll, priceBonat: 8),
      );
    });

    test('no offer when every count is above 0', () {
      final b = _brief(
        c,
        'line_hay.01',
        inventory: {for (final t in boosterTileOrder) t: 1},
      );
      expect(b.buyOffer, isNull);
    });

    test('locked: hidden, and no offer', () {
      final b = _brief(c, 'line_hay.01', boostersLocked: true);
      expect(b.boostersHidden, isTrue);
      expect(b.buyOffer, isNull);
    });
  });
}
