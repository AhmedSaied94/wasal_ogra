import 'package:wassal/core/config/config_source.dart';
import 'package:wassal/core/config/tunable.dart';

/// The defaults from `assets/config/tunables.json`, the last layer.
final class BundledConfigSource implements ConfigSource {
  BundledConfigSource(Map<String, Object?> values)
    : _values = Map.unmodifiable(values);

  final Map<String, Object?> _values;

  /// A registered key always has a valid default; `tunables_defaults_test`
  /// guards that, so a miss here is a build error, not bad remote data.
  @override
  T read<T extends Object>(Tunable<T> key) =>
      key.parse(_values[key.key]) ??
      (throw StateError('No valid bundled default for "${key.key}".'));
}
