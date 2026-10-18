import 'package:wassal/core/config/config_source.dart';
import 'package:wassal/core/config/tunable.dart';

/// A layer of overrides over [fallback]. A missing key, or a value of the
/// wrong type, falls through to [fallback] (FR-035).
final class OverrideConfigSource implements ConfigSource {
  OverrideConfigSource(Map<String, Object?> overrides, {required this.fallback})
    : _overrides = Map.unmodifiable(overrides);

  final Map<String, Object?> _overrides;
  final ConfigSource fallback;

  @override
  T read<T extends Object>(Tunable<T> key) =>
      key.parse(_overrides[key.key]) ?? fallback.read(key);
}
