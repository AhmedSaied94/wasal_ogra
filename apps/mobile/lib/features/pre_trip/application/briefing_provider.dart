// The card's briefing, rebuilt when the economy, the pack or the first
// session changes: a booster bought on the card shows at once
// (specs/013-m08-home-result, contracts/pre-trip-card.md).
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wassal/core/content/content_providers.dart';
import 'package:wassal/core/economy/economy_providers.dart';
import 'package:wassal/core/progress/application/player_progress_provider.dart';
import 'package:wassal/features/onboarding/onboarding_providers.dart';
import 'package:wassal/features/pre_trip/domain/briefing.dart' as domain;
import 'package:wassal/features/pre_trip/domain/briefing.dart'
    show TripBriefing;
import 'package:wassal/features/pre_trip/domain/met_set.dart';

part 'briefing_provider.g.dart';

/// [tripId]'s briefing, or null when the active pack lacks it.
@riverpod
TripBriefing? tripBriefing(Ref ref, String tripId) {
  final content = ref.watch(contentSourceProvider);
  final progress = ref.watch(playerProgressProvider);
  return domain.tripBriefing(
    content,
    tripId: tripId,
    progress: progress,
    inventory: ref.watch(economyViewProvider).inventory,
    met: metSet(content, progress),
    boostersLocked: ref.watch(firstSessionProvider).boostersLocked,
  );
}
