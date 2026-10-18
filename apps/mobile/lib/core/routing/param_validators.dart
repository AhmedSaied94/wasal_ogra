import 'package:wassal/core/glossary/ids.dart';

/// Accepts or rejects one route parameter value.
typedef ParamValidator = bool Function(String value);

/// Route parameter rules from contracts/routes.md (glossary §3.6). A failing
/// rule sends the player to الموقف (FR-022).
abstract final class ParamValidators {
  static final _tripId = RegExp(r'^(line_[a-z]+)\.(\d{2})$');
  static final _itemId = RegExp(r'^(salon|kitchen|bedroom)\.[a-z0-9_]+$');

  /// `<line_id>.<NN>` with a known line, e.g. `line_hay.01`.
  static bool tripId(String value) {
    final match = _tripId.firstMatch(value);
    return match != null && LineId.fromWire(match[1]!) != null;
  }

  static bool lineId(String value) => LineId.fromWire(value) != null;

  static bool vehicleId(String value) => VehicleId.fromWire(value) != null;

  /// `<room>.<id>`, e.g. `salon.nish`.
  static bool itemId(String value) => _itemId.hasMatch(value);

  static bool chapterId(String value) => ChapterId.fromWire(value) != null;
}
