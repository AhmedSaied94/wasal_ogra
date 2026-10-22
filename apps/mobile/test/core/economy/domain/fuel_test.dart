import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/economy/domain/economy_state.dart';
import 'package:wassal/core/economy/domain/fuel.dart';

// The fuel rules, exact to the millisecond (contracts/fuel-and-time.md
// "Fuel"), with max 5 and regen 20 min.

const _max = 5;
const _minute = 60000;
const _regen = 20 * _minute;

/// 09:00 on the tests' day, plus [minutes].
int _at(int minutes) => 1792659600000 + minutes * _minute;

FuelState _regenerate(FuelState s, int t, {int max = _max}) =>
    regenerate(s, t, max: max, regenMs: _regen);

FuelView _view(FuelState s, int t, {int max = _max}) =>
    fuelView(s, t, max: max, regenMs: _regen);

void main() {
  group('the worked examples', () {
    final full = FuelState(liters: 5, countedFromMs: _at(-60));

    test('1. full at 09:00, a start at 09:00', () {
      final s = spendOne(_regenerate(full, _at(0)), _at(0), max: _max);
      expect(s, FuelState(liters: 4, countedFromMs: _at(0)));
      final view = _view(s, _at(0));
      expect(view.nextLiterAtMs, _at(20));
      expect(view.fullAtMs, _at(20));
    });

    test('2. then a start at 09:07 keeps counting from 09:00', () {
      final first = spendOne(full, _at(0), max: _max);
      final s = spendOne(_regenerate(first, _at(7)), _at(7), max: _max);
      expect(s, FuelState(liters: 3, countedFromMs: _at(0)));
      final view = _view(s, _at(7));
      expect(view.nextLiterAtMs, _at(20));
      expect(view.fullAtMs, _at(40));
    });

    test('3. at 09:45 the tank is full since 09:40', () {
      final s = FuelState(liters: 3, countedFromMs: _at(0));
      expect(
        _regenerate(s, _at(45)),
        FuelState(liters: 5, countedFromMs: _at(40)),
      );
      final view = _view(s, _at(45));
      expect(view.liters, 5);
      expect(view.nextLiterAtMs, isNull);
      expect(view.fullAtMs, isNull);
    });

    test('4. fuel_max lowered to 4 while holding 5', () {
      final five = FuelState(liters: 5, countedFromMs: _at(0));
      // 5 kept, not counting.
      expect(_regenerate(five, _at(60), max: 4), five);
      expect(_view(five, _at(60), max: 4).nextLiterAtMs, isNull);
      // A start: 4, still not counting (4 is the max).
      final four = spendOne(five, _at(60), max: 4);
      expect(four, FuelState(liters: 4, countedFromMs: _at(0)));
      expect(_regenerate(four, _at(200), max: 4), four);
      // Another start: 3, counting from that moment.
      final three = spendOne(four, _at(70), max: 4);
      expect(three, FuelState(liters: 3, countedFromMs: _at(70)));
      expect(_view(three, _at(70), max: 4).nextLiterAtMs, _at(90));
    });
  });

  group('regenerate', () {
    test('adds one liter per full interval, keeping the remainder', () {
      final s = FuelState(liters: 1, countedFromMs: _at(0));
      expect(_regenerate(s, _at(19)), s);
      expect(
        _regenerate(s, _at(20)),
        FuelState(liters: 2, countedFromMs: _at(20)),
      );
      expect(
        _regenerate(s, _at(59) + 59999),
        FuelState(liters: 3, countedFromMs: _at(40)),
      );
    });

    test('a time before countedFrom adds nothing', () {
      final s = FuelState(liters: 2, countedFromMs: _at(30));
      expect(_regenerate(s, _at(0)), s);
    });

    test('leaves a tank above the maximum alone', () {
      final s = FuelState(liters: 7, countedFromMs: _at(0));
      expect(_regenerate(s, _at(500)), s);
    });

    test('keeps the unlimited window', () {
      final s = FuelState(
        liters: 1,
        countedFromMs: _at(0),
        unlimitedUntilMs: _at(30),
      );
      expect(_regenerate(s, _at(20)).unlimitedUntilMs, _at(30));
      expect(_regenerate(s, _at(200)).unlimitedUntilMs, _at(30));
    });

    test('a raised maximum counts from the moment the tank last filled', () {
      // Full at 5 since 09:40; fuel_max becomes 7 at 10:30.
      final s = FuelState(liters: 5, countedFromMs: _at(40));
      expect(
        _regenerate(s, _at(90), max: 7),
        FuelState(liters: 7, countedFromMs: _at(80)),
      );
      expect(
        _regenerate(s, _at(65), max: 7),
        FuelState(liters: 6, countedFromMs: _at(60)),
      );
    });

    test('a new regen interval applies only after the point given', () {
      // Up to 09:30 at 20 minutes, then 10 minutes.
      final s = FuelState(liters: 1, countedFromMs: _at(0));
      final at930 = _regenerate(s, _at(30));
      expect(at930, FuelState(liters: 2, countedFromMs: _at(20)));
      final at1000 = regenerate(
        at930,
        _at(60),
        max: _max,
        regenMs: 10 * _minute,
      );
      expect(at1000, FuelState(liters: 5, countedFromMs: _at(50)));
    });
  });

  group('spendOne', () {
    test('leaving the maximum starts the countdown', () {
      final s = FuelState(liters: 5, countedFromMs: _at(0));
      expect(spendOne(s, _at(10), max: _max).countedFromMs, _at(10));
    });

    test('from above the maximum down to it keeps countedFrom', () {
      final s = FuelState(liters: 6, countedFromMs: _at(0));
      expect(
        spendOne(s, _at(10), max: _max),
        FuelState(liters: 5, countedFromMs: _at(0)),
      );
    });

    test('below the maximum keeps countedFrom', () {
      final s = FuelState(liters: 3, countedFromMs: _at(0));
      expect(spendOne(s, _at(10), max: _max).countedFromMs, _at(0));
    });

    test('an empty tank holds at 0', () {
      final s = FuelState(liters: 0, countedFromMs: _at(0));
      expect(spendOne(s, _at(10), max: _max), s);
    });
  });

  group('fillToMax', () {
    test('fills and starts counting from t', () {
      final s = FuelState(
        liters: 1,
        countedFromMs: _at(0),
        unlimitedUntilMs: _at(90),
      );
      expect(
        fillToMax(s, _at(10), max: _max),
        FuelState(liters: 5, countedFromMs: _at(10), unlimitedUntilMs: _at(90)),
      );
    });

    test('is refused at or above the maximum', () {
      expect(
        fillToMax(const FuelState(liters: 5, countedFromMs: 0), 1, max: _max),
        isNull,
      );
      expect(
        fillToMax(const FuelState(liters: 6, countedFromMs: 0), 1, max: _max),
        isNull,
      );
    });
  });

  group('extendUnlimited', () {
    test('starts a new window at t', () {
      final s = FuelState(liters: 2, countedFromMs: _at(0));
      expect(extendUnlimited(s, _at(10)).unlimitedUntilMs, _at(70));
    });

    test('extends a running window from its end', () {
      final s = FuelState(
        liters: 2,
        countedFromMs: _at(0),
        unlimitedUntilMs: _at(40),
      );
      expect(extendUnlimited(s, _at(10)).unlimitedUntilMs, _at(100));
    });

    test('after a window ended, starts again at t', () {
      final s = FuelState(
        liters: 2,
        countedFromMs: _at(0),
        unlimitedUntilMs: _at(40),
      );
      expect(extendUnlimited(s, _at(50)).unlimitedUntilMs, _at(110));
    });

    test('changes no liters', () {
      final s = FuelState(liters: 2, countedFromMs: _at(0));
      final extended = extendUnlimited(s, _at(10));
      expect(extended.liters, 2);
      expect(extended.countedFromMs, _at(0));
    });
  });

  test('isUnlimited is false at the end of the window', () {
    final s = FuelState(
      liters: 0,
      countedFromMs: _at(0),
      unlimitedUntilMs: _at(60),
    );
    expect(isUnlimited(s, _at(59)), isTrue);
    expect(isUnlimited(s, _at(60)), isFalse);
    expect(
      isUnlimited(const FuelState(liters: 0, countedFromMs: 0), _at(0)),
      isFalse,
    );
  });

  group('fuelView', () {
    test('null times at or above the maximum', () {
      for (final liters in [5, 6]) {
        final view = _view(
          FuelState(liters: liters, countedFromMs: _at(0)),
          _at(10),
        );
        expect(view.liters, liters);
        expect(view.max, _max);
        expect(view.nextLiterAtMs, isNull);
        expect(view.fullAtMs, isNull);
      }
    });

    test('the window only while it runs', () {
      final s = FuelState(
        liters: 5,
        countedFromMs: _at(0),
        unlimitedUntilMs: _at(60),
      );
      expect(_view(s, _at(59)).unlimitedUntilMs, _at(60));
      expect(_view(s, _at(60)).unlimitedUntilMs, isNull);
    });

    test('an empty tank fills over max × regen', () {
      final view = _view(FuelState(liters: 0, countedFromMs: _at(0)), _at(0));
      expect(view.nextLiterAtMs, _at(20));
      expect(view.fullAtMs, _at(100));
    });
  });

  test('regenMsOf and the window constant', () {
    expect(regenMsOf(20), _regen);
    expect(unlimitedWindowMs, 60 * _minute);
  });
}
