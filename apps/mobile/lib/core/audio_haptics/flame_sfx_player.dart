import 'dart:async';

import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/foundation.dart';
import 'package:wassal/core/audio_haptics/sfx.dart';

/// Overlapping effects one pool each (research R18).
const _maxPlayers = 3;

/// [SfxPlayer] on audioplayers' pools, one per effect, in low-latency mode.
final class FlameSfxPlayer implements SfxPlayer {
  final _pools = <Sfx, AudioPool>{};
  Future<void>? _loading;

  @override
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    for (final sfx in Sfx.values) {
      try {
        _pools[sfx] = await AudioPool.create(
          source: AssetSource(sfx.assetPath),
          maxPlayers: _maxPlayers,
          playerMode: PlayerMode.lowLatency,
        );
      } on Object catch (error) {
        // A device without audio still plays the trip, in silence.
        debugPrint('sfx ${sfx.file} did not load: $error');
      }
    }
  }

  @override
  void play(Sfx sfx) {
    final pool = _pools[sfx];
    if (pool == null) return;
    unawaited(
      pool.start().then<void>(
        (_) {},
        onError: (Object error) {
          debugPrint('sfx ${sfx.file} did not play: $error');
        },
      ),
    );
  }

  @override
  Future<void> dispose() async {
    final pools = _pools.values.toList();
    _pools.clear();
    _loading = null;
    for (final pool in pools) {
      await pool.dispose();
    }
  }
}
