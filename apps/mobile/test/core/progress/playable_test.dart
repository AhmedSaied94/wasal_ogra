// The phone-only progression rules (specs/014-m09-lines-vehicles,
// contracts/progress-rules.md "Guarantees"): never more permissive than the
// port of the server's rules, the story trips of US5 by name, and the
// vehicles' sale states.
import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/content/domain/content_source.dart';
import 'package:wassal/core/economy/domain/economy_state.dart' as economy;
import 'package:wassal/core/economy/domain/op.dart';
import 'package:wassal/core/economy/domain/rules.dart';
import 'package:wassal/core/economy/domain/spend_rules.dart';
import 'package:wassal/core/economy/domain/wire.dart';
import 'package:wassal/core/progress/domain/playable.dart';
import 'package:wassal/core/progress/domain/player_progress.dart';
import 'package:wassal/core/progress/domain/unlocks.dart';

import '../../helpers/economy.dart';
import '../../helpers/progress.dart';

/// The sweep's depth (contracts/progress-rules.md).
const _depth = 8;

String _t(String line, int n) => '$line.${n.toString().padLeft(2, '0')}';

/// Every trip of [c], by line order then trip number.
List<String> _allTrips(ContentSource c) => [
  for (final line in c.lines)
    for (final trip in c.tripsOf(line.lineId)) trip.tripId,
];

/// Every state reachable from [root] by finishing a playable trip (at one
/// star), buying a vehicle for sale, or buying a priced chapter, at most
/// [_depth] steps.
List<PlayerProgress> _reachable(ContentSource c, PlayerProgress root) {
  final trips = _allTrips(c);
  final seen = <String>{};
  final states = <PlayerProgress>[];
  var frontier = [root];
  String key(PlayerProgress p) => [
    ...(p.bestStars.keys.toList()..sort()),
    '|',
    ...([for (final (kind, id) in p.owned) '${kind.name}:$id']..sort()),
  ].join(' ');
  for (var level = 0; level <= _depth; level++) {
    final next = <PlayerProgress>[];
    for (final p in frontier) {
      if (!seen.add(key(p))) continue;
      states.add(p);
      for (final id in trips) {
        if (p.finished(id) || !tripPlayable(c, p, id)) continue;
        next.add(
          PlayerProgress(bestStars: {...p.bestStars, id: 1}, owned: p.owned),
        );
      }
      for (final vehicle in c.vehicles) {
        if (vehicleSale(c, p, vehicle.vehicleId) is! ForSale) continue;
        next.add(
          PlayerProgress(
            bestStars: p.bestStars,
            owned: {
              ...p.owned,
              (SkuKind.vehicle, vehicleWire[vehicle.vehicleId]!),
            },
          ),
        );
      }
      for (final chapter in c.chapters) {
        final sku = chapterWire[chapter.chapterId]!;
        if (c.price(SkuKind.chapter, sku) == null ||
            p.owns(SkuKind.chapter, sku) ||
            !chapterUnlocked(c, p, chapter.chapterId)) {
          continue;
        }
        next.add(
          PlayerProgress(
            bestStars: p.bestStars,
            owned: {...p.owned, (SkuKind.chapter, sku)},
          ),
        );
      }
    }
    frontier = next;
  }
  return states;
}

/// M05's economy state for [p] with [jenehat]: what `validateBuy` reads.
economy.EconomyState _economyOf(PlayerProgress p, int jenehat) =>
    economy.EconomyState(
      jenehat: jenehat,
      bonat: 0,
      fuel: const economy.FuelState(liters: 5, countedFromMs: testEpochMs),
      ownership: {
        for (final owned in p.owned)
          owned: economy.Owned(kind: owned.$1, acquiredAtMs: testEpochMs),
      },
    );

void _neverMorePermissive(ContentSource c, List<PlayerProgress> roots) {
  final trips = _allTrips(c);
  var checked = 0;
  for (final root in roots) {
    for (final p in _reachable(c, root)) {
      for (final id in trips) {
        if (tripPlayable(c, p, id)) {
          expect(tripUnlocked(c, p, id), isTrue, reason: '$id in $p');
        }
      }
      for (final vehicle in c.vehicles) {
        if (vehicleSale(c, p, vehicle.vehicleId) case ForSale(
          :final priceJenehat,
        )) {
          final decision = validateBuy(
            _economyOf(p, priceJenehat),
            BuyRequest(
              kind: SkuKind.vehicle,
              skuId: vehicleWire[vehicle.vehicleId]!,
            ),
            ruleContext(content: c),
          );
          expect(
            decision,
            isA<Validated>(),
            reason: '${vehicle.vehicleId} in $p',
          );
        }
      }
      checked++;
    }
  }
  expect(checked, greaterThan(10));
}

/// line_hay's regular trips `.01`–`.19` of [draftShaped] finished.
Map<String, int> get _hayRegular => {
  for (var n = 1; n <= 19; n++) _t('line_hay', n): 1,
};

void main() {
  group('never more permissive than the server', () {
    test('the sample pack, at depth $_depth', () {
      _neverMorePermissive(sampleContent(), [PlayerProgress.empty]);
    });

    test('the draft-shaped pack, at depth $_depth from a new player and from '
        'line_hay finished', () {
      _neverMorePermissive(draftContent(), [
        PlayerProgress.empty,
        player(_hayRegular),
        player(_hayRegular, {microOld}),
      ]);
    });
  });

  group('the story trips (US5)', () {
    final c = draftContent();

    test('line_gamaa.01 is locked without the microbus in every chapter', () {
      for (final p in [
        PlayerProgress.empty,
        player(_hayRegular),
        player({..._hayRegular, 'line_hay.20': 3}),
        player(_hayRegular, {shabka}),
      ]) {
        expect(tripPlayable(c, p, 'line_gamaa.01'), isFalse, reason: '$p');
      }
      // With the microbus, once ch1 before it is complete too.
      expect(tripPlayable(c, player({}, {microOld}), 'line_gamaa.01'), isFalse);
      expect(
        tripPlayable(c, player(_hayRegular, {microOld}), 'line_gamaa.01'),
        isTrue,
      );
    });

    test('line_hay.20 opens exactly when .01–.19 have a star', () {
      for (var n = 0; n <= 19; n++) {
        final p = player({for (var i = 1; i <= n; i++) _t('line_hay', i): 1});
        expect(
          tripPlayable(c, p, 'line_hay.20'),
          n == 19,
          reason: 'after $n trips',
        );
        // The server's rule opens it from the start.
        expect(tripUnlocked(c, p, 'line_hay.20'), isTrue);
      }
    });

    test('.18 waits for the shabka after .17, while .19 is playable', () {
      final upTo17 = {for (var n = 1; n <= 17; n++) _t('line_gamaa', n): 1};
      final before = player({..._hayRegular, ...upTo17}, {microOld});
      expect(tripPlayable(c, before, 'line_gamaa.18'), isFalse);
      expect(tripPlayable(c, before, 'line_gamaa.19'), isTrue);
      final after = player({..._hayRegular, ...upTo17}, {microOld, shabka});
      expect(tripPlayable(c, after, 'line_gamaa.18'), isTrue);
    });

    test('after the shabka, .18 is playable with .19–.22 done', () {
      final p = player(
        {
          ..._hayRegular,
          for (var n = 1; n <= 22; n++)
            if (n != 18) _t('line_gamaa', n): 2,
        },
        {microOld, shabka},
      );
      expect(tripPlayable(c, p, 'line_gamaa.18'), isTrue);
    });

    test('a regular trip answers as the server rule does', () {
      final p = player({'line_hay.01': 1});
      for (final id in ['line_hay.01', 'line_hay.02', 'line_hay.03']) {
        expect(tripPlayable(c, p, id), tripUnlocked(c, p, id), reason: id);
      }
    });
  });

  group('vehicles', () {
    test('the starter is the player\'s and has no price', () {
      final c = draftContent();
      expect(
        vehicleSale(c, PlayerProgress.empty, VehicleId.tuktuk),
        isA<Owned>(),
      );
      final starterPriced = sampleWith((json) {
        (json['catalog']! as Map<String, Object?>)['prices'] = [
          ...((json['catalog']! as Map<String, Object?>)['prices']!
              as List<Object?>),
          {
            'amount': 100,
            'currency': 'JENEHAT',
            'sku_id': 'tuktuk',
            'sku_kind': 'vehicle',
          },
        ];
      });
      expect(
        vehicleSale(starterPriced, PlayerProgress.empty, VehicleId.tuktuk),
        isA<Owned>(),
      );
    });

    test('the next vehicle is for sale at its catalog price', () {
      expect(
        vehicleSale(draftContent(), PlayerProgress.empty, VehicleId.microOld),
        isA<ForSale>().having((s) => s.priceJenehat, 'price', 3200),
      );
      expect(
        vehicleSale(draftContent(), player({}, {microOld}), VehicleId.microOld),
        isA<Owned>(),
      );
    });

    test('a vehicle after one the player lacks needs that one first', () {
      final c = artboardContent();
      expect(
        vehicleSale(c, PlayerProgress.empty, VehicleId.microNew),
        isA<NeedsFirst>().having(
          (s) => s.vehicle,
          'vehicle',
          VehicleId.microOld,
        ),
      );
      expect(
        vehicleSale(c, PlayerProgress.empty, VehicleId.microSafar),
        isA<NeedsFirst>().having(
          (s) => s.vehicle,
          'vehicle',
          VehicleId.microOld,
        ),
      );
      expect(
        vehicleSale(c, player({}, {microOld}), VehicleId.microSafar),
        isA<NeedsFirst>().having(
          (s) => s.vehicle,
          'vehicle',
          VehicleId.microNew,
        ),
      );
      expect(
        vehicleSale(c, player({}, {microOld}), VehicleId.microNew),
        isA<ForSale>().having((s) => s.priceJenehat, 'price', 5000),
      );
    });

    test('no price, or a price in BONAT, is not for sale', () {
      final noPrice = sampleWith((json) {
        final catalog = json['catalog']! as Map<String, Object?>;
        catalog['prices'] = [
          for (final price in catalog['prices']! as List<Object?>)
            if ((price! as Map<String, Object?>)['sku_id'] != 'micro_old')
              price,
        ];
      });
      expect(
        vehicleSale(noPrice, PlayerProgress.empty, VehicleId.microOld),
        isA<NoPrice>(),
      );
      final inBonat = sampleWith((json) {
        final catalog = json['catalog']! as Map<String, Object?>;
        for (final price in catalog['prices']! as List<Object?>) {
          final p = price! as Map<String, Object?>;
          if (p['sku_id'] == 'micro_old') p['currency'] = 'BONAT';
        }
      });
      expect(
        vehicleSale(inBonat, PlayerProgress.empty, VehicleId.microOld),
        isA<NoPrice>(),
      );
    });

    test('the current vehicle is the last owned by order', () {
      final c = artboardContent();
      expect(
        currentVehicle(c, PlayerProgress.empty)?.vehicleId,
        VehicleId.tuktuk,
      );
      expect(
        currentVehicle(c, player({}, {microOld}))?.vehicleId,
        VehicleId.microOld,
      );
      expect(
        currentVehicle(
          c,
          player({}, {(SkuKind.vehicle, 'micro_new')}),
        )?.vehicleId,
        VehicleId.microNew,
      );
    });
  });

  group('unknown ids', () {
    test('answer false, NoPrice or null', () {
      final sample = sampleContent();
      expect(tripPlayable(sample, PlayerProgress.empty, 'line_x.01'), isFalse);
      // The sample has no micro_new.
      expect(
        vehicleSale(sample, PlayerProgress.empty, VehicleId.microNew),
        isA<NoPrice>(),
      );
      final none = sampleWith((json) => json['vehicles'] = <Object?>[]);
      expect(currentVehicle(none, PlayerProgress.empty), isNull);
    });
  });
}
