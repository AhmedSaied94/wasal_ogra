import 'package:wassal/core/config/tunable.dart';

/// Reads balancing values (contracts/tunables.md). Sources layer in
/// priority order: a valid override, then (from M15) remote config, then
/// the bundled default. Never throws for a registered key.
abstract interface class ConfigSource {
  T read<T extends Object>(Tunable<T> key);
}
