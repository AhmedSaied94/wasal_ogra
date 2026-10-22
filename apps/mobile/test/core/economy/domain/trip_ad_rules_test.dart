import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/economy/domain/economy_refusal.dart';
import 'package:wassal/core/economy/domain/economy_state.dart';
import 'package:wassal/core/economy/domain/op.dart';
import 'package:wassal/core/economy/domain/rules.dart';

import '../../../helpers/economy.dart';

// The in-trip `ad_reward` placements, and the one only the server grants
// (contracts/operations.md "ad_reward").

const _rules = ProductionRules();

final _trip = UnfinishedTrip(
  startTxn: txnIdOf(50),
  tripId: 'line_hay.01',
  contentVersion: 1,
  maxEarningsJenehat: 20,
  startedAtMs: testEpochMs,
);

EconomyState _player({UnfinishedTrip? trip}) => EconomyState(
  jenehat: 0,
  bonat: 0,
  fuel: const FuelState(liters: 4, countedFromMs: testEpochMs),
  unfinished: trip,
);

Decision _ad(EconomyState s, AdPlacement placement) =>
    _rules.validate(s, AdRewardRequest(placement), ruleContext(id: 9));

void main() {
  group('trip_revive', () {
    test('refused with no trip, and once revived', () {
      expect(
        declinedCode(_ad(_player(), AdPlacement.tripRevive)),
        EconomyRefusal.noTrip,
      );
      expect(
        declinedCode(
          _ad(
            _player(trip: _trip.copyWith(revived: true)),
            AdPlacement.tripRevive,
          ),
        ),
        EconomyRefusal.alreadyRevived,
      );
    });

    test('sets revived and references the start', () {
      final s = _player(trip: _trip);
      final op = validatedOp(_ad(s, AdPlacement.tripRevive));
      expect(
        canonicalJson(op.payload),
        '{"ad_placement":"trip_revive","ref":"${_trip.startTxn.value}"}',
      );
      expect(op.ref, _trip.startTxn);
      expect(op.jenehatDelta + op.bonatDelta + op.fuelDelta, 0);
      final after = _rules.apply(s, op);
      expect(after.unfinished, _trip.copyWith(revived: true));
      expect(_rules.stillValid(after, op), isFalse);
      expect(_rules.stillValid(s, op), isTrue);
    });
  });

  group('traffic_jam', () {
    test('refused with no trip', () {
      expect(
        declinedCode(_ad(_player(), AdPlacement.trafficJam)),
        EconomyRefusal.noTrip,
      );
    });

    test('one per trip, then cap_reached', () {
      final s = _player(trip: _trip);
      final op = validatedOp(_ad(s, AdPlacement.trafficJam));
      expect(
        canonicalJson(op.payload),
        '{"ad_placement":"traffic_jam","ref":"${_trip.startTxn.value}"}',
      );
      final after = _rules.apply(s, op);
      expect(after.unfinished?.trafficJamAds, 1);
      expect(
        declinedCode(_ad(after, AdPlacement.trafficJam)),
        EconomyRefusal.capReached,
      );
      expect(_rules.stillValid(after, op), isFalse);
    });

    test("another trip's cap is its own", () {
      final s = _player(trip: _trip.copyWith(trafficJamAds: 1));
      final next = s.copyWith(
        unfinished: () => UnfinishedTrip(
          startTxn: txnIdOf(51),
          tripId: 'line_hay.02',
          contentVersion: 1,
          maxEarningsJenehat: 30,
          startedAtMs: testEpochMs,
        ),
      );
      validatedOp(_ad(next, AdPlacement.trafficJam));
    });
  });

  test('morning_piggy is the server\'s to grant', () {
    expect(
      declinedCode(_ad(_player(trip: _trip), AdPlacement.morningPiggy)),
      EconomyRefusal.serverOnly,
    );
  });
}
