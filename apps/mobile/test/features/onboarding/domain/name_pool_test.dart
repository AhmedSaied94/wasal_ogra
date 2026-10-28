import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/features/onboarding/domain/name_rules.dart';
import 'package:wassal/features/onboarding/domain/name_suggestions.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

// The suggested names (specs/012-m07-onboarding/contracts/name.md
// "Suggestions"): the ARB's `namePool`, and the picks the Name card makes.

List<String> get _pool =>
    namePoolOf(lookupAppLocalizations(const Locale('ar')).namePool);

void main() {
  group('namePool', () {
    test('has at least 20 names, with no duplicates', () {
      expect(_pool.length, greaterThanOrEqualTo(20));
      expect(_pool.toSet().length, _pool.length);
    });

    test('every name passes NameRules unchanged', () {
      for (final name in _pool) {
        expect(NameRules.check(name), NameOk(name), reason: name);
      }
    });

    test('parsing trims each part and drops empty ones', () {
      expect(namePoolOf(' حمادة ،سيد،، عبده ،'), ['حمادة', 'سيد', 'عبده']);
      expect(namePoolOf(''), isEmpty);
    });
  });

  group('NameSuggestions', () {
    test('the first pick follows the seed', () {
      final a = NameSuggestions(_pool, seed: 7);
      final b = NameSuggestions(_pool, seed: 7);
      expect(a.first, b.first);
      expect(_pool, contains(a.first));
    });

    test('another never returns the name showing', () {
      final suggestions = NameSuggestions(_pool, seed: 1);
      var showing = suggestions.first;
      for (var i = 0; i < 200; i++) {
        final next = suggestions.another(showing);
        expect(next, isNot(showing));
        expect(_pool, contains(next));
        showing = next;
      }
    });

    test('another of a typed name is any pooled name', () {
      final suggestions = NameSuggestions(_pool, seed: 3);
      expect(_pool, contains(suggestions.another('Hamada')));
    });

    test('a pool of one keeps it; an empty pool suggests nothing', () {
      final one = NameSuggestions(const ['سيد'], seed: 0);
      expect(one.first, 'سيد');
      expect(one.another('سيد'), 'سيد');
      final none = NameSuggestions(const <String>[], seed: 0);
      expect(none.first, '');
      expect(none.another('x'), '');
    });
  });
}
