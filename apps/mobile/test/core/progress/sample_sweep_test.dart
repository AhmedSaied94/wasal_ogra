// The progression rules over every state a new player can reach by playing
// (specs/013-m08-home-result, contracts/progress-rules.md "Tests",
// quickstart §2): finishing startable trips, up to six, on the sample pack
// and the progression pack. Each state's unlocks are written out by hand.
import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/content/domain/content_source.dart';
import 'package:wassal/core/progress/domain/unlocks.dart';

import '../../helpers/economy.dart';
import '../../helpers/progress.dart';

/// What one state opens: trips (by short name), lines, chapters, and the
/// current chapter.
typedef _Opens = ({
  String trips,
  Set<LineId> lines,
  Set<ChapterId> chapters,
  ChapterId current,
});

/// Short names: `h1` is line_hay.01, `g2` line_gamaa.02, `s1` line_souq.01.
String _long(String short) {
  final line = switch (short[0]) {
    'h' => 'line_hay',
    'g' => 'line_gamaa',
    _ => 'line_souq',
  };
  return '$line.0${short.substring(1)}';
}

Set<String> _set(String shorts) => {
  for (final s in shorts.split(' ').where((s) => s.isNotEmpty)) _long(s),
};

const _hay = {LineId.lineHay};
const _hayGamaa = {LineId.lineHay, LineId.lineGamaa};
const _ch1 = {ChapterId.ch1FirstJob};
const _ch12 = {ChapterId.ch1FirstJob, ChapterId.ch2HerFather};
const _ch123 = {
  ChapterId.ch1FirstJob,
  ChapterId.ch2HerFather,
  ChapterId.ch3Shabka,
};

/// The sample: line_hay's 01 and 02, and 03 the ch1 story trip, open from
/// the start; line_gamaa needs the micro_old.
const _sampleTable = <String, _Opens>{
  '': (
    trips: 'h1 h3',
    lines: _hay,
    chapters: _ch1,
    current: ChapterId.ch1FirstJob,
  ),
  'h1': (
    trips: 'h1 h2 h3',
    lines: _hay,
    chapters: _ch1,
    current: ChapterId.ch1FirstJob,
  ),
  'h3': (
    trips: 'h1 h3',
    lines: _hay,
    chapters: _ch1,
    current: ChapterId.ch1FirstJob,
  ),
  'h1 h3': (
    trips: 'h1 h2 h3',
    lines: _hay,
    chapters: _ch1,
    current: ChapterId.ch1FirstJob,
  ),
  'h1 h2': (
    trips: 'h1 h2 h3',
    lines: _hay,
    chapters: _ch12,
    current: ChapterId.ch2HerFather,
  ),
  'h1 h2 h3': (
    trips: 'h1 h2 h3',
    lines: _hay,
    chapters: _ch12,
    current: ChapterId.ch2HerFather,
  ),
};

/// The progression pack: line_hay 01 → 03 → 04, then line_gamaa and the
/// ch2 story trip h2; line_souq never.
const _progressionTable = <String, _Opens>{
  '': (
    trips: 'h1',
    lines: _hay,
    chapters: _ch1,
    current: ChapterId.ch1FirstJob,
  ),
  'h1': (
    trips: 'h1 h3',
    lines: _hay,
    chapters: _ch1,
    current: ChapterId.ch1FirstJob,
  ),
  'h1 h3': (
    trips: 'h1 h3 h4',
    lines: _hay,
    chapters: _ch1,
    current: ChapterId.ch1FirstJob,
  ),
  'h1 h3 h4': (
    trips: 'h1 h2 h3 h4 g1',
    lines: _hayGamaa,
    chapters: _ch12,
    current: ChapterId.ch2HerFather,
  ),
  'h1 h2 h3 h4': (
    trips: 'h1 h2 h3 h4 g1',
    lines: _hayGamaa,
    chapters: _ch12,
    current: ChapterId.ch2HerFather,
  ),
  'g1 h1 h3 h4': (
    trips: 'h1 h2 h3 h4 g1 g2',
    lines: _hayGamaa,
    chapters: _ch12,
    current: ChapterId.ch2HerFather,
  ),
  'g1 h1 h2 h3 h4': (
    trips: 'h1 h2 h3 h4 g1 g2',
    lines: _hayGamaa,
    chapters: _ch12,
    current: ChapterId.ch2HerFather,
  ),
  'g1 g2 h1 h3 h4': (
    trips: 'h1 h2 h3 h4 g1 g2',
    lines: _hayGamaa,
    chapters: _ch123,
    current: ChapterId.ch3Shabka,
  ),
  'g1 g2 h1 h2 h3 h4': (
    trips: 'h1 h2 h3 h4 g1 g2',
    lines: _hayGamaa,
    chapters: _ch123,
    current: ChapterId.ch3Shabka,
  ),
};

String _key(Set<String> state) => ([
  for (final id in state)
    '${id.startsWith('line_hay')
            ? 'h'
            : id.startsWith('line_gamaa')
            ? 'g'
            : 's'}'
        '${int.parse(id.split('.').last)}',
]..sort()).join(' ');

void _sweep(ContentSource c, Map<String, _Opens> table) {
  final states = reachableStates(
    c,
    startable: (p, id) => tripUnlocked(c, p, id),
  );
  expect({for (final s in states) _key(s)}, table.keys.toSet());
  final allTrips = [
    for (final line in c.lines)
      for (final trip in c.tripsOf(line.lineId)) trip.tripId,
  ];
  for (final state in states) {
    final key = _key(state);
    final want = table[key]!;
    final p = player({for (final id in state) id: 1});
    expect(
      {
        for (final id in allTrips)
          if (tripUnlocked(c, p, id)) id,
      },
      _set(want.trips),
      reason: 'trips after "$key"',
    );
    expect(
      {
        for (final l in c.lines)
          if (lineUnlocked(c, p, l.lineId)) l.lineId,
      },
      want.lines,
      reason: 'lines after "$key"',
    );
    expect(
      {
        for (final ch in c.chapters)
          if (chapterUnlocked(c, p, ch.chapterId)) ch.chapterId,
      },
      want.chapters,
      reason: 'chapters after "$key"',
    );
    expect(
      currentChapter(c, p)?.chapterId,
      want.current,
      reason: 'current chapter after "$key"',
    );
  }
}

void main() {
  test('the sample pack: every reachable state opens what the table says', () {
    _sweep(sampleContent(), _sampleTable);
  });

  test('the progression pack: every reachable state opens what the table '
      'says', () {
    _sweep(progressionContent(), _progressionTable);
  });
}
