/// Glossary §3.6 content identifiers that the app shell needs before content
/// packs exist: route parameter validation and per-line tunable keys.
///
/// Temporary: B04 generates `packages/content_models` from `content/schemas`,
/// and those generated types replace these enums. Wire names must stay
/// identical to the Shared Contract Glossary.
library;

/// An identifier with a stable wire name taken from the glossary.
abstract interface class WireNamed {
  String get wireName;
}

T? _fromWire<T extends WireNamed>(List<T> values, String wire) {
  for (final value in values) {
    if (value.wireName == wire) return value;
  }
  return null;
}

enum LineId implements WireNamed {
  lineHay('line_hay'),
  lineGamaa('line_gamaa'),
  lineSouq('line_souq'),
  lineMasyaf('line_masyaf'),
  lineSafar('line_safar');

  const LineId(this.wireName);

  @override
  final String wireName;

  static LineId? fromWire(String wire) => _fromWire(values, wire);
}

enum VehicleId implements WireNamed {
  tuktuk('tuktuk'),
  microOld('micro_old'),
  microNew('micro_new'),
  microSafar('micro_safar');

  const VehicleId(this.wireName);

  @override
  final String wireName;

  static VehicleId? fromWire(String wire) => _fromWire(values, wire);
}

enum ChapterId implements WireNamed {
  ch1FirstJob('ch1_first_job'),
  ch2HerFather('ch2_her_father'),
  ch3Shabka('ch3_shabka'),
  ch4Salon('ch4_salon'),
  ch5Kitchen('ch5_kitchen'),
  ch6Bedroom('ch6_bedroom'),
  ch7Wedding('ch7_wedding');

  const ChapterId(this.wireName);

  @override
  final String wireName;

  static ChapterId? fromWire(String wire) => _fromWire(values, wire);
}

enum RoomId implements WireNamed {
  salon('salon'),
  kitchen('kitchen'),
  bedroom('bedroom');

  const RoomId(this.wireName);

  @override
  final String wireName;

  static RoomId? fromWire(String wire) => _fromWire(values, wire);
}
