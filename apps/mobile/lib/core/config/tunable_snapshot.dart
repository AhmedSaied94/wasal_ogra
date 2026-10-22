import 'package:wassal/core/config/config_source.dart';
import 'package:wassal/core/config/tunable.dart';

/// Every tunable's current value by key, with enum values as their wire
/// strings: the flat map `TripParams.fromTunables` reads
/// (specs/008-m02-trip-screen, trip-controller.md "Opening").
Map<String, Object?> tunableSnapshot(ConfigSource config) => {
  for (final tunable in Tunable.all) tunable.key: _wire(config.read(tunable)),
};

Object? _wire(Object value) => switch (value) {
  PreTripCardMode(:final wire) || TripHintsMode(:final wire) => wire,
  _ => value,
};
