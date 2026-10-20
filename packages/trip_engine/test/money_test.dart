// Pieces and the money tables (rules.md §14).
import 'dart:convert';

import 'package:content_models/content_models.dart';
import 'package:test/test.dart';
import 'package:trip_engine/src/money.dart';

void main() {
  group('Pieces', () {
    test('adds, removes and totals', () {
      final pieces = Pieces({100: 2, 50: 1});
      expect(pieces.total, 250);
      expect(pieces.length, 3);
      expect(pieces.plusOne(500).total, 750);
      expect(pieces.plus(Pieces({100: 1})).count(100), 3);
      expect(pieces.minusOne(100).count(100), 1);
      expect(pieces.minus(Pieces({100: 2})), Pieces({50: 1}));
      expect(pieces.minus(pieces).isEmpty, isTrue);
      expect(pieces.contains(Pieces({100: 2})), isTrue);
      expect(pieces.contains(Pieces({100: 3})), isFalse);
    });

    test('removing a missing piece is an error', () {
      expect(() => Pieces({100: 1}).minusOne(50), throwsArgumentError);
      expect(
        () => Pieces({100: 1}).minus(Pieces({100: 2})),
        throwsArgumentError,
      );
    });

    test('holds only denominations, each at least once', () {
      expect(() => Pieces({300: 1}), throwsArgumentError);
      expect(() => Pieces({100: 0}), throwsArgumentError);
      expect(() => Pieces.ofList([100, 25]), throwsArgumentError);
    });

    test('is in ascending order and unmodifiable', () {
      final pieces = Pieces({1000: 1, 50: 2, 500: 1});
      expect(pieces.counts.keys, [50, 500, 1000]);
      expect(pieces.toList(), [50, 50, 500, 1000]);
      expect(() => pieces.counts[100] = 1, throwsUnsupportedError);
      expect(Pieces.ofList([500, 50, 50]), Pieces({50: 2, 500: 1}));
    });

    test('has a canonical JSON form', () {
      expect(jsonEncode(Pieces({100: 2})), '{"100":2}');
      expect(
        canonicalJson(Pieces({50: 1, 100: 2}).toJson()),
        '{"100":2,"50":1}',
      );
      expect(Pieces.fromJson({'100': 2, '50': 1}), Pieces({50: 1, 100: 2}));
      expect(Pieces.empty.toJson(), isEmpty);
    });

    test('fromJson refuses bad keys and counts', () {
      for (final bad in [
        {'300': 1},
        {'100': 0},
        {'100': '2'},
        {'abc': 1},
      ]) {
        expect(
          () => Pieces.fromJson(bad),
          throwsFormatException,
          reason: '$bad',
        );
      }
    });
  });

  test('isDenomination', () {
    expect(denominations, [50, 100, 500, 1000, 2000, 5000, 10000, 20000]);
    expect(denominations.every(isDenomination), isTrue);
    expect(isDenomination(300), isFalse);
    expect(isDenomination(0), isFalse);
  });

  group('fewest pieces (§14.3)', () {
    test('4150 is 2000×2, 100 and 50', () {
      expect(fewestPieces(4150), Pieces({2000: 2, 100: 1, 50: 1}));
    });
    test('50 is one coin, 0 is nothing', () {
      expect(fewestPieces(50), Pieces({50: 1}));
      expect(fewestPieces(0), Pieces.empty);
    });
    test('the largest note comes first', () {
      expect(
        fewestPieces(37950),
        Pieces({20000: 1, 10000: 1, 5000: 1, 2000: 1, 500: 1, 100: 4, 50: 1}),
      );
    });
    test('refuses amounts that are not multiples of 50', () {
      expect(() => fewestPieces(75), throwsArgumentError);
      expect(() => fewestPieces(-50), throwsArgumentError);
    });
  });

  group('break-down table (§14.1)', () {
    test('every row totals its note', () {
      for (final note in [1000, 2000, 5000, 10000, 20000]) {
        expect(breakDown(note)!.total, note, reason: '$note');
      }
    });
    test('the rows', () {
      expect(breakDown(1000), Pieces({500: 1, 100: 4, 50: 2}));
      expect(breakDown(2000), Pieces({1000: 1, 500: 1, 100: 4, 50: 2}));
      expect(breakDown(5000), Pieces({2000: 2, 500: 1, 100: 4, 50: 2}));
      expect(
        breakDown(10000),
        Pieces({5000: 1, 2000: 2, 500: 1, 100: 4, 50: 2}),
      );
      expect(
        breakDown(20000),
        Pieces({10000: 1, 5000: 1, 2000: 2, 500: 1, 100: 4, 50: 2}),
      );
    });
    test('500 and the coins have no row', () {
      expect(breakDown(500), isNull);
      expect(breakDown(100), isNull);
      expect(breakDown(50), isNull);
    });
  });

  test('the change bag is 50×2, 100×3 and 500×2 (§14.2)', () {
    expect(changeBag, Pieces({50: 2, 100: 3, 500: 2}));
  });

  group('change-request pieces (§14.4)', () {
    test('1000 from {500:1, 100:5}', () {
      expect(
        changeRequestPieces(1000, Pieces({500: 1, 100: 5})),
        Pieces({500: 1, 100: 5}),
      );
    });
    test('1000 from {500:1, 100:4} has no selection', () {
      expect(changeRequestPieces(1000, Pieces({500: 1, 100: 4})), isNull);
    });
    test('5000 from {2000:2, 500:1, 100:5}', () {
      expect(
        changeRequestPieces(5000, Pieces({2000: 2, 500: 1, 100: 5})),
        Pieces({2000: 2, 500: 1, 100: 5}),
      );
    });
    test('1000 from {500:1, 100:3, 50:4}', () {
      expect(
        changeRequestPieces(1000, Pieces({500: 1, 100: 3, 50: 4})),
        Pieces({500: 1, 100: 3, 50: 4}),
      );
    });
    test('backtracking finds what greedy misses', () {
      // Greedy takes the 5000 and then can't make the last 1000 from 2000s.
      expect(
        changeRequestPieces(10000, Pieces({5000: 1, 2000: 5})),
        Pieces({2000: 5}),
      );
    });
    test('the note itself is never used', () {
      expect(changeRequestPieces(1000, Pieces({1000: 3})), isNull);
    });
    test('the most of each denomination is tried first', () {
      expect(
        changeRequestPieces(1000, Pieces({500: 2, 100: 10, 50: 20})),
        Pieces({500: 2}),
      );
    });
    test('a large tray with no selection is answered quickly', () {
      final tray = Pieces({10000: 1, 5000: 3, 2000: 9, 500: 39, 100: 4, 50: 1});
      expect(
        changeRequestPieces(20000, Pieces({500: 39, 100: 4, 50: 1})),
        isNull,
      );
      expect(changeRequestPieces(20000, tray)!.total, 20000);
    });
  });
}
