import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wassal/core/audio_haptics/flame_sfx_player.dart';
import 'package:wassal/core/audio_haptics/haptics.dart';
import 'package:wassal/core/audio_haptics/sfx.dart';

part 'audio_haptics_providers.g.dart';

@Riverpod(keepAlive: true)
SfxPlayer sfxPlayer(Ref ref) {
  final player = FlameSfxPlayer();
  ref.onDispose(player.dispose);
  return player;
}

@Riverpod(keepAlive: true)
Haptics haptics(Ref ref) => const SystemHaptics();
