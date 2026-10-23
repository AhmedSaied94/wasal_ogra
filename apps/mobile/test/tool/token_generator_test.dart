import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/theme/tokens/curves.dart';

import '../../tool/design/token_generator.dart';

// The token generator (specs/008.5-m21-design-refresh,
// contracts/design-tokens.md "Generation", "Names", "Not generated").

Map<String, Object?> _design() =>
    jsonDecode(File('../../docs/design/tokens.json').readAsStringSync())
        as Map<String, Object?>;

/// The smallest tokens file that names one value of every group.
Map<String, Object?> _minimal() => {
  r'$schema_note': 'a note',
  'color': {
    'primary': '#1A4B8C',
    'primary.lip': '#0F2F5A',
    'ink.2': '#4A4558',
    'scrim': 'rgba(29,26,43,0.60)',
  },
  'color_rules': ['danger never carries white text'],
  'dashboard': {'bg': '#2A2633'},
  'station': [
    {'order': 1, 'bg': '#3B2A6B', 'letter': '#FFFFFF'},
  ],
  'station_rules': 'by order',
  'money_note': {
    'fare': {'bg': '#BFE3C9', 'lip': '#8CC59E', 'text': '#1D1A2B'},
  },
  'denomination': {
    '0.5': {'label': 'x', 'bg': '#D9D4E2', 'kind': 'coin'},
    '200': {'label': 'y', 'bg': '#F7D9A8', 'kind': 'note'},
  },
  'scene': {'seat.hi': '#F2A08A'},
  'character': {
    'skin': ['#F1C7A0', '#E0A97A'],
  },
  'font': {
    'display': {'family': 'Marhey'},
  },
  'type': {
    'display.l': {
      'family': 'Marhey',
      'weight': 700,
      'size': 28,
      'lineHeight': 1.2,
      'use': 'screen title',
    },
    'display.m': {
      'family': 'Marhey',
      'weight': 700,
      'size': '22–26 (24)',
      'lineHeight': 1.2,
    },
    'label': {
      'family': 'Readex Pro',
      'weight': 600,
      'size': 12,
      'lineHeight': 1.2,
    },
  },
  'digits': {'default': 'arabic-indic'},
  'radius': {'card': 22},
  'lip': {
    'primary.m': {'y': 5, 'color': '#0F2F5A'},
  },
  'ring': {
    'hot': {'width': 3, 'color': '#F2542D', 'inset': false},
  },
  'space': {'12': 12},
  'layout': {
    'trip': {
      'faces': {
        'near': {
          'r': 41,
          'scale': 1.0,
          'y': 308,
          'x': [62, 176, 290],
          'tag': 30,
        },
      },
    },
  },
  'motion': {
    'sheetIn': {'ms': 280, 'curve': 'easeOutCubic'},
    'dialogIn': {'ms': 220, 'curve': 'easeOutBack(1.2)'},
    'moneyHop': {
      'ms': {'hay': 1300},
      'curve': 'easeInOut',
    },
    'reducedMotion': 'disables shake',
  },
};

void main() {
  group('names', () {
    final out = generateTokens(_minimal());

    test('colours: dotted keys become camelCase', () {
      expect(out, contains('static const primaryLip = Color(0xFF0F2F5A);'));
      expect(out, contains('static const ink2 = Color(0xFF4A4558);'));
      expect(out, contains('static const dashboardBg = Color(0xFF2A2633);'));
      expect(out, contains('static const sceneSeatHi = Color(0xFFF2A08A);'));
    });

    test('money notes: fill, lip and text', () {
      expect(out, contains('static const noteFare = Color(0xFFBFE3C9);'));
      expect(out, contains('static const noteFareLip = Color(0xFF8CC59E);'));
      expect(out, contains('static const noteFareText = Color(0xFF1D1A2B);'));
    });

    test('denominations: their fills, never their labels', () {
      expect(out, contains('static const denom050 = Color(0xFFD9D4E2);'));
      expect(out, contains('static const denom200 = Color(0xFFF7D9A8);'));
      expect(out, isNot(contains("'x'")));
    });

    test('every single colour by name, for the gallery', () {
      expect(out, contains('static const named = <String, Color>{'));
      expect(out, contains("'primaryLip': primaryLip,"));
      expect(out, contains("'noteFareText': noteFareText,"));
      expect(out, isNot(contains("'characterSkin'")));
    });

    test('lists of colours and the stations', () {
      expect(out, contains('static const characterSkin = <Color>['));
      expect(out, contains('class StationColors'));
      expect(
        out,
        contains('(bg: Color(0xFF3B2A6B), letter: Color(0xFFFFFFFF))'),
      );
    });

    test('type styles', () {
      expect(out, contains('static const displayL = TextStyle('));
      expect(out, contains("fontFamily: 'ReadexPro'"));
      expect(out, contains('fontWeight: FontWeight.w700'));
      expect(out, contains("FontVariation('wght', 700)"));
    });

    test('lips: the shadow and its depth', () {
      expect(out, contains('static const primaryM = BoxShadow('));
      expect(out, contains('static const double primaryMDepth = 5;'));
    });

    test('rings, radii, space', () {
      expect(out, contains('static const hot = RingSpec('));
      expect(out, contains('static const double card = 22;'));
      expect(out, contains('static const double s12 = 12;'));
    });

    test('the trip layout', () {
      expect(out, contains('static const tripNear = FaceRowSpec('));
      expect(out, contains('x: <double>[62, 176, 290]'));
    });

    test('motion: a duration and its curve', () {
      expect(
        out,
        contains('static const sheetIn = Duration(milliseconds: 280);'),
      );
      expect(out, contains('static const sheetInCurve = Curves.easeOutCubic;'));
      expect(out, contains('static const dialogInCurve = EaseOutBack(1.2);'));
    });
  });

  test('colours: #RRGGBB is opaque, rgba() keeps its alpha', () {
    final out = generateTokens(_minimal());
    expect(out, contains('static const primary = Color(0xFF1A4B8C);'));
    // 0.60 × 255 = 153 = 0x99.
    expect(out, contains('static const scrim = Color(0x991D1A2B);'));
  });

  test('a range with a bracketed value uses that value', () {
    expect(
      generateTokens(_minimal()),
      matches(RegExp(r'displayM = TextStyle\([^)]*fontSize: 24[,\s]')),
    );
  });

  test('notes, rules, fonts, digits and moneyHop are not emitted', () {
    final out = generateTokens(_minimal());
    for (final word in [
      'moneyHop',
      'reducedMotion',
      'schema',
      'Rules',
      'digits',
      'arabic',
      'screen title',
      'hay',
    ]) {
      expect(out, isNot(contains(word)), reason: word);
    }
  });

  test('an unreadable value throws, naming its key', () {
    final json = _minimal();
    (json['color']! as Map<String, Object?>)['broken'] = 'blue-ish';
    expect(
      () => generateTokens(json),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('color.broken'),
        ),
      ),
    );
    final curve = _minimal();
    ((curve['motion']! as Map<String, Object?>)['sheetIn']!
            as Map<String, Object?>)['curve'] =
        'wobbly';
    expect(
      () => generateTokens(curve),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('motion.sheetIn.curve'),
        ),
      ),
    );
  });

  test('two runs give the same output', () {
    expect(generateTokens(_design()), generateTokens(_design()));
  });

  test('every type style has even leading and a size of at least 12', () {
    final out = generateTokens(_design());
    final styles = RegExp(r'static const (\w+) = TextStyle\(([^;]*)\);')
        .allMatches(out)
        .toList();
    expect(styles, hasLength(13));
    for (final style in styles) {
      final body = style.group(2)!;
      expect(
        body,
        contains('leadingDistribution: TextLeadingDistribution.even'),
        reason: style.group(1),
      );
      final size = double.parse(
        RegExp(r'fontSize: ([0-9.]+)').firstMatch(body)!.group(1)!,
      );
      expect(size, greaterThanOrEqualTo(12), reason: style.group(1));
    }
  });

  group('EaseOutBack', () {
    test('starts at 0, ends at 1, and overshoots between', () {
      const curve = EaseOutBack(1.2);
      expect(curve.transform(0), 0);
      expect(curve.transform(1), 1);
      final peak = [for (var t = 0.05; t < 1; t += 0.05) curve.transform(t)]
          .reduce((a, b) => a > b ? a : b);
      expect(peak, greaterThan(1));
    });

    test('follows 1 + (k + 1)(t − 1)³ + k(t − 1)²', () {
      const k = 1.4;
      const t = 0.3;
      expect(
        const EaseOutBack(k).transform(t),
        closeTo(1 + (k + 1) * -0.343 + k * 0.49, 1e-9),
      );
    });
  });
}
