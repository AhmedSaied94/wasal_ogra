import 'package:flutter/foundation.dart';

/// A step of startup that the loading bar counts (specs/008.5-m21-design-refresh
/// data-model.md "BootProgress").
enum BootStep {
  settings,
  tunables,
  content,
  database,
  economy,

  /// The Rive file (contracts/rive-characters.md "How the app uses it"). It
  /// never fails: without the file, everything is drawn with static art.
  art,

  /// The first open's wait (specs/011-m06-identity-sync, research R6). Not
  /// one of `appStartup`'s steps: boot marks it when the wait ends, at once
  /// on later launches, so the road bar reaches its end.
  account,
}

/// How far startup is: the steps finished, and the one that failed. A base
/// class, so the design sample can show the board's 62%.
@immutable
base class BootProgress {
  const BootProgress({this.done = const {}, this.failed});

  /// The steps, in boot order.
  static const steps = BootStep.values;

  final Set<BootStep> done;

  /// The step that failed, or null.
  final BootStep? failed;

  /// From 0 to 1.
  double get value => done.length / steps.length;

  BootProgress withDone(BootStep step) =>
      BootProgress(done: {...done, step}, failed: failed);

  BootProgress withFailure(BootStep step) =>
      BootProgress(done: done, failed: step);

  @override
  bool operator ==(Object other) =>
      other is BootProgress &&
      setEquals(other.done, done) &&
      other.failed == failed;

  @override
  int get hashCode => Object.hash(Object.hashAllUnordered(done), failed);

  @override
  String toString() => 'BootProgress(done: $done, failed: $failed)';
}

/// Waits for every step, calling [onDone] as each finishes and [onFailed]
/// when one fails. Completes when all have finished, or with the first
/// failure's error.
Future<void> trackBootSteps(
  Map<BootStep, Future<Object?>> steps, {
  required void Function(BootStep step) onDone,
  required void Function(BootStep step) onFailed,
}) => Future.wait([
  for (final MapEntry(key: step, value: future) in steps.entries)
    future.then<void>(
      (_) => onDone(step),
      onError: (Object error, StackTrace stack) {
        onFailed(step);
        Error.throwWithStackTrace(error, stack);
      },
    ),
]);
