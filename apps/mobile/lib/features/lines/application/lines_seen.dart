// The news the player has seen on Lines (specs/014-m09-lines-vehicles,
// contracts/lines.md "The «new» dot", research R8): kept in the device
// preference `pref.lines_seen`, sorted and comma-joined. A read marker,
// not game state: losing it shows the dot once more.
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wassal/bootstrap/startup.dart';
import 'package:wassal/core/content/content_providers.dart';
import 'package:wassal/core/economy/economy_providers.dart';
import 'package:wassal/core/progress/application/player_progress_provider.dart';
import 'package:wassal/features/lines/domain/lines_news.dart';

part 'lines_seen.g.dart';

/// What is new on Lines now.
@riverpod
Set<String> linesNewsKeys(Ref ref) => linesNews(
  ref.watch(contentSourceProvider),
  ref.watch(playerProgressProvider),
  ref.watch(economyViewProvider).jenehat,
);

@Riverpod(keepAlive: true)
class LinesSeenNotifier extends _$LinesSeenNotifier {
  static const key = 'pref.lines_seen';

  @override
  Set<String> build() {
    final saved = ref.read(settingsStoreProvider).requireValue.readString(key);
    if (saved != null) return decode(saved);
    // The first read: what the player already has isn't news (an install,
    // or an update from M08).
    final now = ref.read(linesNewsKeysProvider);
    _write(now);
    return now;
  }

  /// Marks [news] seen.
  void markSeen(Set<String> news) {
    if (state.containsAll(news)) return;
    state = {...state, ...news};
    _write(state);
  }

  void _write(Set<String> seen) => ref
      .read(settingsStoreProvider)
      .requireValue
      .writeString(key, encode(seen));

  static String encode(Set<String> keys) => (keys.toList()..sort()).join(',');

  static Set<String> decode(String value) => {
    for (final key in value.split(','))
      if (key.isNotEmpty) key,
  };
}
