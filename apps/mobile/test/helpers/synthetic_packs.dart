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
