// What the device perf runs share: every frame's timing while they run, and
// the rates the budgets are written in (specs/008-m02-trip-screen research
// R25, specs/012.5-m22-animated-scenes research R14).
import 'dart:async';
import 'dart:ui' show FramePhase, FrameTiming;

import 'package:flutter/scheduler.dart';

const _second = 1000000;

/// Collects every frame's timing while it runs.
final class FrameTimings {
  FrameTimings() {
    SchedulerBinding.instance.addTimingsCallback(_add);
  }

  final timings = <FrameTiming>[];
  final _waiting = <(int, Completer<FrameTiming>)>[];

  void _add(List<FrameTiming> batch) {
    timings.addAll(batch);
    for (final timing in batch) {
      final start = timing.timestampInMicroseconds(FramePhase.buildStart);
      _waiting.removeWhere((w) {
        if (start < w.$1) return false;
        w.$2.complete(timing);
        return true;
      });
    }
  }

  /// The first frame whose build starts at or after [micros] (the same
  /// clock as `Timeline.now`).
  Future<FrameTiming> after(int micros) {
    final done = Completer<FrameTiming>();
    _waiting.add((micros, done));
    return done.future;
  }

  void dispose() => SchedulerBinding.instance.removeTimingsCallback(_add);
}

/// When [t]'s raster finished.
int rasterEnd(FrameTiming t) =>
    t.timestampInMicroseconds(FramePhase.rasterFinish);

/// Average fps, and the fewest frames in any one-second window.
({double average, int worstWindow}) frameRates(List<FrameTiming> frames) {
  final ends = [for (final f in frames) rasterEnd(f)]..sort();
  final span = ends.last - ends.first;
  var worst = ends.length;
  var j = 0;
  for (var i = 0; i < ends.length && ends[i] + _second <= ends.last; i++) {
    while (j < ends.length && ends[j] < ends[i] + _second) {
      j++;
    }
    worst = worst < j - i ? worst : j - i;
  }
  return (average: (ends.length - 1) * _second / span, worstWindow: worst);
}
