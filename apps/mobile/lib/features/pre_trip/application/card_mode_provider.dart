// The pre-trip card's setting (specs/013-m08-home-result, research R6): a
// device preference, like the digit style, falling back to the
// `pre_trip_card_mode` tunable. And whether a start skips the card.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wassal/bootstrap/startup.dart';
import 'package:wassal/core/config/config_providers.dart';
import 'package:wassal/core/config/tunable.dart';
import 'package:wassal/core/content/content_providers.dart';
import 'package:wassal/core/progress/application/player_progress_provider.dart';
import 'package:wassal/features/pre_trip/domain/card_mode.dart';
import 'package:wassal/features/pre_trip/domain/met_set.dart';

part 'card_mode_provider.g.dart';

@Riverpod(keepAlive: true)
class PreTripCardModeNotifier extends _$PreTripCardModeNotifier {
  static const key = 'pref.pre_trip_card';

  @override
  PreTripCardMode build() {
    final saved = ref.watch(settingsStoreProvider).requireValue.readString(key);
    for (final mode in PreTripCardMode.values) {
      if (mode.wire == saved) return mode;
    }
    return ref.watch(configSourceProvider).read(Tunable.preTripCardMode);
  }

  /// Applies [mode] at once, then persists it.
  Future<void> set(PreTripCardMode mode) async {
    state = mode;
    await ref
        .read(settingsStoreProvider)
        .requireValue
        .writeString(key, mode.wire);
  }
}

/// Whether a start of [tripId] goes straight to the trip: nothing new, not
/// a story trip, and the setting «في الجديد بس». A trip the pack lacks
/// shows the card, which sends the player home.
bool skipPreTripCard(WidgetRef ref, String tripId) {
  final content = ref.read(contentSourceProvider);
  final trip = content.trip(tripId);
  if (trip == null) return false;
  final met = metSet(content, ref.read(playerProgressProvider));
  final always = ref.read(preTripCardModeProvider) == PreTripCardMode.always;
  return !shouldShowCard(trip, met, always: always);
}
