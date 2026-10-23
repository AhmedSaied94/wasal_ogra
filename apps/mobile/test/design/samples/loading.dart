import 'dart:async';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:wassal/bootstrap/boot_progress.dart';
import 'package:wassal/bootstrap/startup.dart';

// The `Loading` artboard as the app draws it: `BootScreen` with startup
// still running and the road bar at the board's sample value, 62%.

/// The board's sample progress.
const loadingSampleValue = 0.62;

/// Startup that never finishes, with the bar at [loadingSampleValue].
List<Override> loadingSampleOverrides() => [
  appStartupProvider.overrideWith((ref) => Completer<void>().future),
  bootProgressProvider.overrideWith(_SampleProgressNotifier.new),
];

/// Five steps can't make 62%: this one reports the board's value.
final class _SampleProgress extends BootProgress {
  const _SampleProgress();

  @override
  double get value => loadingSampleValue;
}

final class _SampleProgressNotifier extends BootProgressNotifier {
  @override
  BootProgress build() => const _SampleProgress();
}
