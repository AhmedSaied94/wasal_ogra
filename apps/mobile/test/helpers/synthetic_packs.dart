// Packs larger than the sample, for the load-time budgets
// (specs/006-m04-content-loader/research.md R15). Built from the sample, so
// they decode with the real models.
import 'dart:convert';
import 'dart:io';

import 'content.dart';

const _twoMebibytes = 2097152;

Map<String, Object?> _trip(Map<String, Object?> template, String id) => {
  ...template,
  'trip_id': id,
};

/// The MVP's size: 20 trips on line_hay, 30 on line_gamaa, the sample's
/// four chapters and every speech pool. [sample] is the sample pack's JSON;
/// on a device it comes from the asset bundle, not from disk.
Map<String, Object?> _mvpJson(Map<String, Object?>? sample) {
  final json = sample ?? samplePackJson();
  final trips = (json['trips']! as List<Object?>)
      .cast<Map<String, dynamic>>()
      .map((t) => t.cast<String, Object?>());
  Map<String, Object?> first(String line) =>
      trips.firstWhere((t) => t['line_id'] == line);
  String id(String line, int n) => '$line.${n.toString().padLeft(2, '0')}';
  return {
    ...json,
    'trips': [
      for (var n = 1; n <= 20; n++) _trip(first('line_hay'), id('line_hay', n)),
      for (var n = 1; n <= 30; n++)
        _trip(first('line_gamaa'), id('line_gamaa', n)),
    ],
  };
}

EncodedPack mvpSizePack({Map<String, Object?>? sample}) =>
    encodePackFile(_mvpJson(sample));

/// Pseudo-random letters from the Arabic block, from a seeded xorshift32,
/// so the pack is the same on every run and compresses like real text.
final class _Letters {
  _Letters(this._state);

  int _state;

  int _next() {
    var x = _state;
    x ^= (x << 13) & 0xFFFFFFFF;
    x ^= x >> 17;
    x ^= (x << 5) & 0xFFFFFFFF;
    return _state = x;
  }

  String line(int length) => String.fromCharCodes([
    for (var i = 0; i < length; i++)
      // A space now and then, so the text has words.
      _next() % 7 == 0 ? 0x20 : 0x0628 + _next() % 35,
  ]);
}

/// [mvpSizePack] plus generated speech lines, until the file is at least
/// 2 MiB.
EncodedPack twoMebibytePack({Map<String, Object?>? sample}) {
  final json = _mvpJson(sample);
  final letters = _Letters(20261021);
  final pools = (json['speech_pools']! as List<Object?>)
      .cast<Map<String, dynamic>>();
  final extra = <Map<String, Object?>>[];
  var pack = encodePackFile(json);
  while (pack.bytes.length < _twoMebibytes) {
    // Grow by the estimated shortfall, at least 500 lines at a time.
    final perLine = _compressedPerLine(letters);
    final missing = _twoMebibytes - pack.bytes.length;
    final count = (missing / perLine).ceil().clamp(500, 1 << 20);
    for (var i = 0; i < count; i++) {
      extra.add({
        'text': {'ar-EG': letters.line(120)},
      });
    }
    json['speech_pools'] = [
      for (final (index, pool) in pools.indexed)
        {
          ...pool,
          'lines': [
            ...(pool['lines'] as List<Object?>),
            for (var i = index; i < extra.length; i += pools.length) extra[i],
          ],
        },
    ];
    pack = encodePackFile(json);
  }
  return pack;
}

double _compressedPerLine(_Letters letters) {
  final sample = [
    for (var i = 0; i < 200; i++)
      {
        'text': {'ar-EG': letters.line(120)},
      },
  ];
  final bytes = GZipCodec(level: 9).encode(utf8.encode(jsonEncode(sample)));
  return bytes.length / sample.length;
}

/// A pack for the progression sweeps (specs/013-m08-home-result, T004,
/// T013), built from the sample:
/// - line_hay (start): trips 01, 03 and 04 regular, 02 a story trip mid-line
///   that ch2 names, so it stays locked until ch1 is complete;
/// - line_gamaa (once line_hay is complete): trips 01 and 02, on the tuktuk;
/// - line_souq (with the micro_old, which the sweeps never buy): one trip;
/// - ch1 completes line_hay, ch2 line_gamaa, then the sample's ch3 and ch4.
Map<String, Object?> progressionPackJson() {
  final json = samplePackJson();
  List<Map<String, Object?>> list(String key) => [
    for (final item in json[key]! as List<Object?>)
      (item! as Map<String, dynamic>).cast<String, Object?>(),
  ];
  final lines = {for (final l in list('lines')) l['line_id']: l};
  final trips = list('trips');
  Map<String, Object?> trip(String from, String id, String line, String kind) {
    final template = trips.firstWhere((t) => t['trip_id'] == from);
    return {
      ...template,
      'trip_id': id,
      'line_id': line,
      'kind': kind,
      'vehicle_id': line == 'line_souq' ? 'micro_old' : 'tuktuk',
      'seats': line == 'line_souq'
          ? trips.firstWhere((t) => t['trip_id'] == 'line_gamaa.01')['seats']
          : trips.firstWhere((t) => t['trip_id'] == 'line_hay.01')['seats'],
    };
  }

  return {
    ...json,
    'lines': [
      lines['line_hay'],
      {
        ...lines['line_gamaa']!,
        'unlock': {'kind': 'line_complete', 'line_id': 'line_hay'},
      },
      {
        ...lines['line_gamaa']!,
        'line_id': 'line_souq',
        'order': 3,
        'unlock': {'kind': 'vehicle', 'vehicle_id': 'micro_old'},
      },
    ],
    'trips': [
      trip('line_hay.01', 'line_hay.01', 'line_hay', 'regular'),
      trip('line_hay.03', 'line_hay.02', 'line_hay', 'story'),
      trip('line_hay.02', 'line_hay.03', 'line_hay', 'regular'),
      trip('line_hay.01', 'line_hay.04', 'line_hay', 'regular'),
      trip('line_gamaa.01', 'line_gamaa.01', 'line_gamaa', 'regular'),
      trip('line_gamaa.02', 'line_gamaa.02', 'line_gamaa', 'regular'),
      trip('line_gamaa.01', 'line_souq.01', 'line_souq', 'regular'),
    ],
    'chapters': [
      for (final chapter in list('chapters'))
        switch (chapter['chapter_id']) {
          'ch1_first_job' => {
            for (final MapEntry(:key, :value) in chapter.entries)
              if (key != 'story_trip_id') key: value,
          },
          'ch2_her_father' => {
            ...chapter,
            'goal': {'kind': 'complete_line', 'line_id': 'line_gamaa'},
            'story_trip_id': 'line_hay.02',
          },
          _ => chapter,
        },
    ],
  };
}

/// The sample's [key] list, as maps a builder can copy.
List<Map<String, Object?>> _list(Map<String, Object?> json, String key) => [
  for (final item in json[key]! as List<Object?>)
    (item! as Map<String, dynamic>).cast<String, Object?>(),
];

String _tripId(String line, int n) => '$line.${n.toString().padLeft(2, '0')}';

/// [prices] with the [sku] of [kind] at [amount] JENEHAT, added or replaced.
List<Map<String, Object?>> _withPrice(
  List<Map<String, Object?>> prices,
  String kind,
  String sku,
  int amount,
) => [
  for (final price in prices)
    if (price['sku_kind'] != kind || price['sku_id'] != sku) price,
  {'amount': amount, 'currency': 'JENEHAT', 'sku_id': sku, 'sku_kind': kind},
];

/// The release draft's shape (specs/014-m09-lines-vehicles, T012), built
/// from the sample:
/// - line_hay (start, tuktuk): 19 regular trips and the story trip `.20`;
/// - line_gamaa (micro_old): 30 trips, the story trips `.01` and `.18`;
/// - ch1 completes line_hay (story `line_hay.20`), ch2 owns the micro_old
///   (story `line_gamaa.01`), ch3 buys the shabka (story `line_gamaa.18`),
///   then the sample's ch4;
/// - the micro_old at 3,200 and the shabka at 6,000 (the draft's catalog
///   isn't in this repository, so the shabka's price is this pack's own).
Map<String, Object?> draftShaped() {
  final json = samplePackJson();
  final trips = _list(json, 'trips');
  Map<String, Object?> template(String id) =>
      trips.firstWhere((t) => t['trip_id'] == id);
  Map<String, Object?> trip(String from, String id, String kind) => {
    ...template(from),
    'trip_id': id,
    'kind': kind,
  };
  const gamaaStories = {1, 18};
  return {
    ...json,
    'trips': [
      for (var n = 1; n <= 19; n++)
        trip('line_hay.01', _tripId('line_hay', n), 'regular'),
      trip('line_hay.03', _tripId('line_hay', 20), 'story'),
      for (var n = 1; n <= 30; n++)
        trip(
          'line_gamaa.01',
          _tripId('line_gamaa', n),
          gamaaStories.contains(n) ? 'story' : 'regular',
        ),
    ],
    'chapters': [
      for (final chapter in _list(json, 'chapters'))
        switch (chapter['chapter_id']) {
          'ch1_first_job' => {...chapter, 'story_trip_id': 'line_hay.20'},
          'ch2_her_father' => {...chapter, 'story_trip_id': 'line_gamaa.01'},
          'ch3_shabka' => {...chapter, 'story_trip_id': 'line_gamaa.18'},
          _ => chapter,
        },
    ],
    'catalog': {
      ...(json['catalog']! as Map<String, dynamic>).cast<String, Object?>(),
      'prices': _withPrice(
        _withPrice(
          _list(
            (json['catalog']! as Map<String, dynamic>).cast<String, Object?>(),
            'prices',
          ),
          'vehicle',
          'micro_old',
          3200,
        ),
        'chapter',
        'ch3_shabka',
        6000,
      ),
    },
  };
}

/// The artboards' four vehicles and five lines (specs/014-m09-lines-vehicles,
/// T012; `Lines`, `LineDetails`, `BuyVehicle`), built from the sample:
/// - the tuktuk and the micro_old («ميكروباص قديم», as the boards name it)
///   as the sample has them; the micro_new (12 seats, 5,000) and the
///   micro_safar (13 seats, 12,000);
/// - line_hay (٧ ج, 20 trips, the story trip `.20`) and line_gamaa (٨٫٥ ج,
///   30 trips with a story trip at `.10` and `.20`); line_souq (١٣ ج, with
///   the micro_new), line_masyaf
///   (١١ ج, after line_souq) and line_safar (٤٣ ج, with the micro_safar),
///   each with two trips; ch1 names `line_hay.20`, ch2 `line_gamaa.10` and
///   ch3 `line_gamaa.20`;
/// - the boards' names and what's new. The boards draw no what's new for
///   line_masyaf and line_safar, so theirs are this pack's own.
Map<String, Object?> artboardLines() {
  final json = samplePackJson();
  final trips = _list(json, 'trips');
  final lines = {for (final l in _list(json, 'lines')) l['line_id']: l};
  final vehicles = {
    for (final v in _list(json, 'vehicles')) v['vehicle_id']: v,
  };
  final oldSeats = (vehicles['micro_old']!['seats']! as List<Object?>)
      .cast<Object?>();
  Map<String, Object?> seat(String row, String col) => {
    'col': col,
    'reachable_by_driver': false,
    'row': row,
    'seat_id': '${row}_$col',
  };
  Map<String, Object?> template(String id) =>
      trips.firstWhere((t) => t['trip_id'] == id);
  Map<String, Object?> trip(String line, int n, String vehicle, String kind) =>
      {
        ...template(line == 'line_hay' ? 'line_hay.01' : 'line_gamaa.01'),
        'trip_id': _tripId(line, n),
        'line_id': line,
        'vehicle_id': vehicle,
        'kind': kind,
      };
  Map<String, Object?> line(
    String id,
    int order,
    String name,
    int fare,
    String whatsNew,
    Map<String, Object?> unlock,
  ) => {
    ...lines['line_gamaa']!,
    'line_id': id,
    'order': order,
    'name': {'ar-EG': name},
    'display_fare_piasters': fare,
    'whats_new': {'ar-EG': whatsNew},
    'unlock': unlock,
  };
  const gamaaStories = {10, 20};
  final catalog = (json['catalog']! as Map<String, dynamic>)
      .cast<String, Object?>();
  return {
    ...json,
    'vehicles': [
      vehicles['tuktuk'],
      {
        ...vehicles['micro_old']!,
        'name': {'ar-EG': 'ميكروباص قديم'},
      },
      {
        ...vehicles['micro_old']!,
        'vehicle_id': 'micro_new',
        'order': 3,
        'name': {'ar-EG': 'ميكروباص جديد'},
        'short_name': {'ar-EG': 'جديد'},
        'seats': [...oldSeats, seat('D', 'r'), seat('D', 'l')],
      },
      {
        ...vehicles['micro_old']!,
        'vehicle_id': 'micro_safar',
        'order': 4,
        'name': {'ar-EG': 'ميكروباص سفر'},
        'short_name': {'ar-EG': 'سفر'},
        'seats': [...oldSeats, seat('D', 'r'), seat('D', 'm'), seat('D', 'l')],
      },
    ],
    'lines': [
      {...lines['line_hay']!, 'display_fare_piasters': 700},
      {
        ...lines['line_gamaa']!,
        'display_fare_piasters': 850,
        'whats_new': {'ar-EG': 'نص الأجرة، الدفع الجماعي، «أنا دافع!»'},
      },
      line('line_souq', 3, 'خط السوق', 1300, 'الشنط والمتهرب', {
        'kind': 'vehicle',
        'vehicle_id': 'micro_new',
      }),
      line('line_masyaf', 4, 'خط المصيف', 1100, 'زحمة الصيف', {
        'kind': 'line_complete',
        'line_id': 'line_souq',
      }),
      line('line_safar', 5, 'خط السفر', 4300, 'الطريق الطويل', {
        'kind': 'vehicle',
        'vehicle_id': 'micro_safar',
      }),
    ],
    'trips': [
      for (var n = 1; n <= 20; n++)
        trip('line_hay', n, 'tuktuk', n == 20 ? 'story' : 'regular'),
      for (var n = 1; n <= 30; n++)
        trip(
          'line_gamaa',
          n,
          'micro_old',
          gamaaStories.contains(n) ? 'story' : 'regular',
        ),
      for (final (id, vehicle) in [
        ('line_souq', 'micro_new'),
        ('line_masyaf', 'micro_new'),
        ('line_safar', 'micro_safar'),
      ])
        for (var n = 1; n <= 2; n++) trip(id, n, vehicle, 'regular'),
    ],
    'chapters': [
      for (final chapter in _list(json, 'chapters'))
        switch (chapter['chapter_id']) {
          'ch1_first_job' => {...chapter, 'story_trip_id': 'line_hay.20'},
          'ch2_her_father' => {...chapter, 'story_trip_id': 'line_gamaa.10'},
          'ch3_shabka' => {...chapter, 'story_trip_id': 'line_gamaa.20'},
          _ => chapter,
        },
    ],
    'catalog': {
      ...catalog,
      'prices': _withPrice(
        _withPrice(_list(catalog, 'prices'), 'vehicle', 'micro_new', 5000),
        'vehicle',
        'micro_safar',
        12000,
      ),
    },
  };
}
