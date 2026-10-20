// The engine's tests take their defaults from the app's bundled tunables, so
// there is one source of balancing values (constitution VIII, research R12).
import 'dart:convert';
import 'dart:io';

import 'package:content_models/content_models.dart';
import 'package:trip_engine/trip_engine.dart';

const tunablesPath = '../../apps/mobile/assets/config/tunables.json';

Map<String, Object?> bundledTunables() =>
    jsonDecode(File(tunablesPath).readAsStringSync()) as Map<String, Object?>;

/// The bundled defaults resolved for [line].
TripParams defaultParams([LineId line = LineId.lineGamaa]) =>
    TripParams.fromTunables(bundledTunables(), line);

/// The defaults for [line] with [overrides] (wire keys) applied.
TripParams paramsWith(
  Map<String, int> overrides, [
  LineId line = LineId.lineGamaa,
]) => TripParams.fromJson({...defaultParams(line).toJson(), ...overrides});
