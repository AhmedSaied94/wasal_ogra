// A line's standing on Lines (specs/014-m09-lines-vehicles, data-model
// `LineStanding`, FR-008, FR-009).
import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/progress/domain/player_progress.dart';
import 'package:wassal/features/lines/domain/line_standing.dart';

import '../../../helpers/economy.dart';
import '../../../helpers/progress.dart';

String _t(String line, int n) => '$line.${n.toString().padLeft(2, '0')}';

LineStanding _of(List<LineStanding> all, LineId id) =>
    all.firstWhere((s) => s.line == id);

void main() {
  group('locked', () {
    test('by a vehicle', () {
      final all = lineStandings(artboardContent(), PlayerProgress.empty);
      expect(
        _of(all, LineId.lineGamaa).state,
        const LineLocked(NeedsVehicle(VehicleId.microOld)),
      );
      expect(
        _of(all, LineId.lineSafar).state,
        const LineLocked(NeedsVehicle(VehicleId.microSafar)),
      );
    });

    test('by another line', () {
      final all = lineStandings(artboardContent(), PlayerProgress.empty);
      expect(
        _of(all, LineId.lineMasyaf).state,
        const LineLocked(AfterLine(LineId.lineSouq)),
      );
    });
  });

  group('current', () {
    test('with its next trip, number and total', () {
      final p = player(
        {
          for (var n = 1; n <= 11; n++) _t('line_gamaa', n): 2,
          'line_hay.01': 3,
          'line_hay.02': 3,
        },
        {microOld},
      );
      final gamaa = _of(lineStandings(artboardContent(), p), LineId.lineGamaa);
      expect(
        gamaa.state,
        const LineCurrent(
          NextInLine(tripId: 'line_gamaa.12', number: 12, total: 30),
        ),
      );
    });

    test('a new player\'s first line starts at its first trip', () {
      final hay = _of(
        lineStandings(sampleContent(), PlayerProgress.empty),
        LineId.lineHay,
      );
      expect(
        hay.state,
        const LineCurrent(
          NextInLine(tripId: 'line_hay.01', number: 1, total: 3),
        ),
      );
    });

    test('the next trip skips a story trip that waits for its chapter', () {
      // The sample's line_hay.03 waits for ch1's goal: .01 and .02.
      final hay = _of(
        lineStandings(sampleContent(), player({'line_hay.01': 1})),
        LineId.lineHay,
      );
      expect((hay.state as LineCurrent).next.tripId, 'line_hay.02');
    });
  });

  group('done', () {
    test('when no playable trip is left without a star', () {
      final hay = _of(
        lineStandings(sampleContent(), player({...hayDone, 'line_hay.03': 2})),
        LineId.lineHay,
      );
      expect(hay.state, const LineDone());
      expect(hay.doneCount, 3);
    });

    test('a newer pack adding trips to a done line makes it current', () {
      final p = player({...hayDone, 'line_hay.03': 2});
      final bigger = sampleWith((json) {
        final trips = entries(json, 'trips');
        json['trips'] = [
          ...trips,
          {
            ...entry(json, 'trips', 'trip_id', 'line_hay.01'),
            'trip_id': 'line_hay.04',
          },
        ];
      });
      expect(
        _of(lineStandings(bigger, p), LineId.lineHay).state,
        const LineCurrent(
          NextInLine(tripId: 'line_hay.04', number: 4, total: 4),
        ),
      );
    });
  });

  group('stars', () {
    test('earned out of three per trip, and the trips done', () {
      final hay = _of(
        lineStandings(sampleContent(), player({'line_hay.01': 3})),
        LineId.lineHay,
      );
      expect(hay.starsEarned, 3);
      expect(hay.starsMax, 9);
      expect(hay.doneCount, 1);
      expect(hay.allThree, isFalse);
    });

    test('allThree when every trip has three', () {
      final hay = _of(
        lineStandings(
          sampleContent(),
          player({'line_hay.01': 3, 'line_hay.02': 3, 'line_hay.03': 3}),
        ),
        LineId.lineHay,
      );
      expect(hay.allThree, isTrue);
      expect(hay.starsEarned, hay.starsMax);
    });
  });

  test('content: the name, what\'s new and the fare', () {
    final hay = _of(
      lineStandings(sampleContent(), PlayerProgress.empty),
      LineId.lineHay,
    );
    expect(hay.name, 'خط الحي');
    expect(hay.whatsNew, isNotEmpty);
    expect(hay.farePiasters, 700);
  });

  test('every line in pack order', () {
    expect(
      [
        for (final s in lineStandings(artboardContent(), PlayerProgress.empty))
          s.line,
      ],
      [
        LineId.lineHay,
        LineId.lineGamaa,
        LineId.lineSouq,
        LineId.lineMasyaf,
        LineId.lineSafar,
      ],
    );
  });

  test('ids the pack lacks are skipped', () {
    // The sample has two lines; progress naming others changes nothing.
    final all = lineStandings(
      sampleContent(),
      player({'line_souq.01': 3}, {(SkuKind.vehicle, 'micro_new')}),
    );
    expect([for (final s in all) s.line], [LineId.lineHay, LineId.lineGamaa]);
    expect(_of(all, LineId.lineHay).starsEarned, 0);
  });
}
