// What the result says of a finished trip (specs/013-m08-home-result,
// data-model `ResultSummary`, research R14, R15): the result's own figures,
// nothing computed from anything else.
import 'dart:convert';

import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/core/economy/domain/economy_state.dart';
import 'package:wassal/features/result/domain/result_args.dart';
import 'package:wassal/features/result/domain/summary.dart';
import 'package:wassal/features/trip/domain/looks.dart';

import '../../../helpers/economy.dart';
import '../../../helpers/trip.dart';

final _start = txnIdOf(7);

Map<String, Object?> _plain(Object? json) =>
    jsonDecode(jsonEncode(json)) as Map<String, Object?>;

/// [fixture]'s finished trip, with [result]'s fields over its result and
/// [definition] changing its definition.
ResultArgs _args(
  String fixture, {
  Map<String, Object?> result = const {},
  void Function(Map<String, Object?> definition)? definition,
  int bestStarsBefore = 0,
  int jenehatBefore = 0,
}) {
  final f = loadFixture(fixture);
  final def = _plain(f.definition.toJson());
  definition?.call(def);
  final trip = TripDefinition.fromJson(def);
  return ResultArgs(
    result: TripResult.fromJson({
      ..._plain(f.expectedResult.toJson()),
      ...result,
    }),
    startTxn: _start,
    replay: ReplayRecord(
      definition: trip,
      seed: f.seed,
      params: f.params,
      commandLog: f.commandLog,
      tMs: f.expectedResult.durationMs,
    ),
    bestStarsBefore: bestStarsBefore,
    jenehatBefore: jenehatBefore,
  );
}

ResultSummary _summary(ResultArgs args, {LastResult? lastResult}) =>
    resultSummary(sampleContent(), args, lastResult: lastResult)!;

Map<String, Object?> _mistake(String passenger, String kind, int amount) => {
  'passenger_id': passenger,
  'kind': kind,
  'amount_piasters': amount,
};

void main() {
  test('the header and the title: the trip, its line, its last stop', () {
    final s = _summary(_args('sample__line_hay_01_three_stars'));
    expect(s.tripId, 'line_hay.01');
    expect(s.tripIndex, 1);
    expect(s.lineName, 'خط الحي');
    // The trip's stops by `at_seconds`; the last one's name.
    expect(s.lastStop, 'الفرن');
  });

  test('a trip whose line the pack lacks has no summary', () {
    final args = _args(
      'sample__line_hay_01_three_stars',
      definition: (d) => d['line_id'] = 'line_souq',
    );
    expect(resultSummary(sampleContent(), args, lastResult: null), isNull);
  });

  test('the star rows are the result\'s flags, in order', () {
    final s = _summary(_args('ending__two_stars'));
    expect(s.stars, 2);
    expect(s.starRows, const [
      StarRow(StarCondition.reached, earned: true),
      StarRow(StarCondition.noFights, earned: true),
      StarRow(StarCondition.noMistakes, earned: false),
    ]);
  });

  test('the breakdown is the result\'s figures, as they are', () {
    // Figures that don't add up stay as they are: nothing is recomputed.
    final s = _summary(
      _args(
        'sample__line_hay_01_three_stars',
        result: {
          'fares_collected_piasters': 7850,
          'tips_piasters': 700,
          'overpaid_piasters': 50,
          'fights': 0,
          'earnings_jenehat': 999,
        },
      ),
    );
    expect(
      s.breakdown,
      const Breakdown(
        faresPiasters: 7850,
        tipsPiasters: 700,
        overpaidPiasters: 50,
        fights: 0,
      ),
    );
    expect(s.payJenehat, 999);
  });

  group('mistake lines', () {
    test('one per mistake, in order, with the look and its label; then '
        'the counts', () {
      final s = _summary(
        _args(
          'ending__one_star',
          definition: (d) {
            final p2 = (d['passengers']! as List<Object?>)[1]!;
            (p2 as Map<String, Object?>)
              ..['archetype'] = 'hajja'
              ..['skin'] = 'hajja_black';
          },
          result: {
            'mistakes': [
              _mistake('p1', 'over', 50),
              _mistake('p2', 'unreturned', 100),
              _mistake('p3', 'not_owed', 300),
            ],
            'fights': 2,
            'missed_stops': 1,
            'lost_fares': 3,
          },
        ),
      );
      final regular = lookFor('worker_blue', Archetype.regular);
      final hagga = lookFor('hajja_black', Archetype.hajja);
      expect(s.mistakeLines, [
        PassengerMistake(
          passengerId: 'p1',
          look: regular,
          labelKey: regular.labelKey,
          feminine: false,
          kind: MistakeKind.over,
          amountPiasters: 50,
        ),
        PassengerMistake(
          passengerId: 'p2',
          look: hagga,
          labelKey: 'tripLookHajja',
          feminine: true,
          kind: MistakeKind.unreturned,
          amountPiasters: 100,
        ),
        PassengerMistake(
          passengerId: 'p3',
          look: regular,
          labelKey: regular.labelKey,
          feminine: false,
          kind: MistakeKind.notOwed,
          amountPiasters: 300,
        ),
        const CountLine(CountKind.fights, 2),
        const CountLine(CountKind.missedStops, 1),
        const CountLine(CountKind.lostFares, 3),
      ]);
    });

    test('a group payer is «الشلة», as in «آخر كلام»', () {
      final s = _summary(
        _args(
          'archetype__group_payer_redirect',
          result: {
            'mistakes': [_mistake('p1', 'over', 100)],
          },
        ),
      );
      final line = s.mistakeLines.single as PassengerMistake;
      expect(line.labelKey, groupLabelKey);
    });

    test('a passenger the trip lacks has the neutral look', () {
      final s = _summary(
        _args(
          'core__over_change_kept',
          result: {
            'mistakes': [_mistake('p9', 'over', 100)],
          },
        ),
      );
      final line = s.mistakeLines.single as PassengerMistake;
      expect(line.labelKey, passengerLabelKey);
      expect(line.feminine, isFalse);
    });

    test('no counts at zero; nothing went wrong, no lines', () {
      final s = _summary(_args('sample__line_hay_01_three_stars'));
      expect(s.mistakeLines, isEmpty);
      expect(s.summary, isNull);
    });
  });

  test('the amount\'s size: 50 is half, 100 is one, the rest other', () {
    expect(amountSizeOf(50), AmountSize.half);
    expect(amountSizeOf(100), AmountSize.one);
    expect(amountSizeOf(150), AmountSize.other);
    expect(amountSizeOf(200), AmountSize.other);
    expect(amountSizeOf(0), AmountSize.other);
  });

  group('the summary', () {
    MistakesSummary? summaryOf(Map<String, Object?> result) =>
        _summary(_args('ending__two_stars', result: result)).summary;

    test('fights cost the second star and the third: the fights', () {
      expect(
        summaryOf({
          'fights': 2,
          'mistakes': [_mistake('p1', 'over', 50)],
          'lost_fares': 1,
        }),
        const MistakesSummary(count: 2, family: SummaryFamily.fights),
      );
    });

    test('mistakes only cost the third: the mistakes', () {
      expect(
        summaryOf({
          'fights': 0,
          'mistakes': [
            _mistake('p1', 'over', 50),
            _mistake('p2', 'over', 50),
            _mistake('p3', 'over', 50),
          ],
          'missed_stops': 1,
        }),
        const MistakesSummary(count: 3, family: SummaryFamily.mistakes),
      );
    });

    test('losses only cost no star: missed stops and lost fares', () {
      expect(
        summaryOf({
          'fights': 0,
          'mistakes': <Object?>[],
          'missed_stops': 1,
          'lost_fares': 2,
        }),
        const MistakesSummary(count: 3, family: SummaryFamily.losses),
      );
    });
  });

  test('first three stars: three now, fewer before', () {
    const three = 'sample__line_hay_01_three_stars';
    expect(_summary(_args(three)).firstThreeStars, isTrue);
    expect(_summary(_args(three, bestStarsBefore: 2)).firstThreeStars, isTrue);
    expect(_summary(_args(three, bestStarsBefore: 3)).firstThreeStars, isFalse);
    expect(_summary(_args('ending__two_stars')).firstThreeStars, isFalse);
  });

  group('the pay', () {
    final args = _args('sample__line_hay_01_three_stars');
    LastResult last({required bool doubled, bool ours = true}) => LastResult(
      startTxn: ours ? _start : txnIdOf(8),
      outcome: TripOutcome.finished,
      earningsJenehat: args.result.earningsJenehat,
      doubled: doubled,
    );

    test('the result\'s earnings', () {
      expect(_summary(args).payJenehat, args.result.earningsJenehat);
      expect(
        _summary(args, lastResult: last(doubled: false)).payJenehat,
        args.result.earningsJenehat,
      );
    });

    test('doubled when the last result is this start\'s, doubled', () {
      expect(
        _summary(args, lastResult: last(doubled: true)).payJenehat,
        2 * args.result.earningsJenehat,
      );
      expect(
        _summary(args, lastResult: last(doubled: true, ours: false)).payJenehat,
        args.result.earningsJenehat,
      );
    });
  });
}
