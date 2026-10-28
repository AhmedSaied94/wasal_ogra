import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/features/onboarding/domain/first_session.dart';
import 'package:wassal/features/onboarding/domain/panel_turns.dart';

import '../../../helpers/economy.dart';
import '../../../helpers/tutorial_content.dart';

// A panel's lines as turns (specs/012.5-m22-animated-scenes, data-model.md
// "Turns", contracts/scene-turns.md "The schedule"): one turn per spoken
// line, in order, after the panel's lead-in, each as long as its line
// within a floor and a ceiling, a pause between them.

Duration _ms(int n) => Duration(milliseconds: n);

/// The scenes' values (research R5).
final _scenes = TurnTimings(
  leadIn: _ms(280),
  perLetter: _ms(60),
  min: _ms(1200),
  max: _ms(4000),
  pause: _ms(300),
);

/// A millisecond a letter, with no lead-in, floor, ceiling or pause: a
/// turn's length is its letter count.
final _unit = TurnTimings(
  leadIn: Duration.zero,
  perLetter: _ms(1),
  min: Duration.zero,
  max: const Duration(hours: 1),
  pause: Duration.zero,
);

PanelLine _line(String speaker, String text) => PanelLine(
  speaker: speaker,
  text: LocalizedText(arEg: text),
);

/// The sample's `opening_stand`: المعلم's line, then the usta's.
final _stand = [
  _line('moallem', 'الركاب بيدفعوا، والفلوس بتيجي لحد الدرج.'),
  _line('usta', 'وأنا أرجّع الباقي لكل واحد.'),
];

TurnsAt _at({required int shown, String? talking, required bool last}) =>
    TurnsAt(shown: shown, talking: talking, lastStarted: last);

void main() {
  test('one turn per spoken line, in order; the caption takes none', () {
    final turns = PanelTurns([
      _line('narrator', 'الموقف، الصبح بدري'),
      ..._stand,
    ], _scenes).turns;
    expect([for (final t in turns) t.speaker], ['moallem', 'usta']);
    expect([for (final t in turns) t.index], [0, 1]);
  });

  test('turns[0].start == leadIn, and turns[i + 1].start == turns[i].end + '
      'pause', () {
    final turns = PanelTurns([
      _line('moallem', 'one two three'),
      _line('usta', 'x'),
      _line('moallem', 'a' * 100),
    ], _scenes).turns;
    expect(turns.first.start, _scenes.leadIn);
    for (var i = 0; i + 1 < turns.length; i++) {
      expect(turns[i + 1].start, turns[i].end + _scenes.pause);
    }
  });

  test('turn.end − turn.start == clamp(perLetter × letters, min, max)', () {
    final turns = PanelTurns([
      // 11 letters: 660 ms, raised to the floor.
      _line('moallem', 'one two three'),
      // 30 letters: 1800 ms.
      _line('usta', 'a' * 30),
      // 100 letters: 6000 ms, cut to the ceiling.
      _line('moallem', 'a' * 100),
    ], _scenes).turns;
    expect(
      [for (final t in turns) t.end - t.start],
      [_ms(1200), _ms(1800), _ms(4000)],
    );
  });

  test('no two turns overlap, and the starts strictly increase', () {
    final turns = PanelTurns([
      for (var i = 0; i < 8; i++) _line(i.isEven ? 'usta' : 'salma', 'x' * i),
    ], _scenes).turns;
    for (var i = 0; i + 1 < turns.length; i++) {
      expect(turns[i + 1].start, greaterThan(turns[i].start));
      expect(turns[i + 1].start, greaterThanOrEqualTo(turns[i].end));
    }
  });

  test('letters are grapheme clusters that aren\'t white space', () {
    // «لمّ»: three code points, the shadda on the mim, two letters.
    expect(PanelTurns([_line('usta', 'لمّ')], _unit).end, _ms(2));
    expect(PanelTurns([_line('usta', 'لم')], _unit).end, _ms(2));
    expect(PanelTurns([_line('usta', ' a \n b ')], _unit).end, _ms(2));
    expect(PanelTurns([_line('usta', 'يلا، على الله.')], _unit).end, _ms(12));
  });

  test('at() through a panel: before, in, between and after its turns', () {
    final turns = PanelTurns(_stand, _scenes);
    expect(turns.end, _ms(4000));
    expect(turns.at(Duration.zero), _at(shown: 0, last: false));
    expect(turns.at(_ms(279)), _at(shown: 0, last: false));
    expect(turns.at(_ms(280)), _at(shown: 1, talking: 'moallem', last: false));
    expect(turns.at(_ms(2379)), _at(shown: 1, talking: 'moallem', last: false));
    expect(turns.at(_ms(2380)), _at(shown: 1, last: false), reason: 'pause');
    expect(turns.at(_ms(2679)), _at(shown: 1, last: false));
    expect(turns.at(_ms(2680)), _at(shown: 2, talking: 'usta', last: true));
    expect(turns.at(_ms(3999)), _at(shown: 2, talking: 'usta', last: true));
    expect(turns.at(_ms(4000)), _at(shown: 2, last: true));
    expect(turns.at(const Duration(minutes: 1)), _at(shown: 2, last: true));
  });

  test('For a panel with no spoken lines, at gives shown 0, talking null '
      'and lastStarted true', () {
    for (final lines in [
      <PanelLine>[],
      [_line('narrator', 'الموقف')],
    ]) {
      final turns = PanelTurns(lines, _scenes);
      expect(turns.turns, isEmpty);
      expect(turns.end, Duration.zero);
      expect(turns.at(Duration.zero), _at(shown: 0, last: true));
    }
  });

  test('TurnsAt equality: the same three fields are equal, and share a '
      'hashCode', () {
    expect(
      _at(shown: 1, talking: 'usta', last: false),
      _at(shown: 1, talking: 'usta', last: false),
    );
    expect(
      _at(shown: 1, talking: 'usta', last: false).hashCode,
      _at(shown: 1, talking: 'usta', last: false).hashCode,
    );
    expect(_at(shown: 1, last: false), isNot(_at(shown: 1, last: true)));
    expect(
      _at(shown: 1, talking: 'usta', last: false),
      isNot(_at(shown: 1, last: false)),
    );
    final turns = PanelTurns(_stand, _scenes);
    expect(turns.at(_ms(500)), turns.at(_ms(2000)), reason: 'one turn');
  });

  test('the same speaker twice: two turns, nobody talking in the pause', () {
    final turns = PanelTurns([
      _line('usta', 'a' * 23),
      _line('usta', 'b' * 23),
    ], _scenes);
    expect([for (final t in turns.turns) t.speaker], ['usta', 'usta']);
    expect(turns.at(_ms(1000)).talking, 'usta');
    expect(turns.at(_ms(1700)), _at(shown: 1, last: false));
    expect(turns.at(_ms(2000)), _at(shown: 2, talking: 'usta', last: true));
  });

  test('TurnTimings refuses min > max, or a negative value', () {
    expect(
      () => TurnTimings(
        leadIn: Duration.zero,
        perLetter: _ms(60),
        min: _ms(2000),
        max: _ms(1000),
        pause: Duration.zero,
      ),
      throwsArgumentError,
    );
    for (final negative in [
      () => TurnTimings(
        leadIn: _ms(-1),
        perLetter: _ms(60),
        min: Duration.zero,
        max: Duration.zero,
        pause: Duration.zero,
      ),
      () => TurnTimings(
        leadIn: Duration.zero,
        perLetter: _ms(60),
        min: Duration.zero,
        max: _ms(10),
        pause: _ms(-5),
      ),
    ]) {
      expect(negative, throwsArgumentError);
    }
  });

  test("the sample's opening ends at 2980, 4000 and 3280 ms (research R5)", () {
    final opening = sceneOf(sampleContent(), 'opening')!;
    expect(
      [for (final p in opening.panels) PanelTurns(p.lines, _scenes).end],
      [_ms(2980), _ms(4000), _ms(3280)],
    );
  });

  test("the sample's the_stand ends at 1480, 1840 and 1780 ms", () {
    final stand = sceneOf(sampleContent(), 'the_stand')!;
    expect(
      [for (final p in stand.panels) PanelTurns(p.lines, _scenes).end],
      [_ms(1480), _ms(1840), _ms(1780)],
    );
  });

  test("the draft's first_sight ends at 1840, 3580 and 3340 ms", () {
    final turns = [
      for (final p in draftFirstSight().panels) PanelTurns(p.lines, _scenes),
    ];
    expect([for (final t in turns) t.end], [_ms(1840), _ms(3580), _ms(3340)]);
    // ch1_salma_asks: سلمى 1800 ms, the pause, the usta 1200 ms.
    expect(
      [for (final t in turns[1].turns) (t.speaker, t.start, t.end)],
      [('salma', _ms(280), _ms(2080)), ('usta', _ms(2380), _ms(3580))],
    );
    // ch1_usta_dreams: the usta twice, 1380 ms each, the pause between.
    expect(
      [for (final t in turns[2].turns) (t.speaker, t.start, t.end)],
      [('usta', _ms(280), _ms(1660)), ('usta', _ms(1960), _ms(3340))],
    );
  });
}
