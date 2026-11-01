// The one way into a trip from Home, the card's launcher, «مشوار تاني» and
// Lines (specs/013-m08-home-result, contracts/home.md "startNextTrip";
// specs/014-m09-lines-vehicles, contracts/line-details.md "Starting a
// trip"): nothing for a trip that may not start; the fuel sheet on an empty
// tank; else the checkpoint, then the card or the trip.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wassal/core/content/content_providers.dart';
import 'package:wassal/core/economy/economy_providers.dart';
import 'package:wassal/core/progress/application/player_progress_provider.dart';
import 'package:wassal/core/progress/domain/playable.dart';
import 'package:wassal/core/routing/nav_guard.dart';
import 'package:wassal/features/home/application/checkpoint.dart';
import 'package:wassal/features/home/application/home_model.dart';
import 'package:wassal/features/onboarding/onboarding_providers.dart';
import 'package:wassal/features/pre_trip/application/card_mode_provider.dart';
import 'package:wassal/features/trip/domain/line_ids.dart';

part 'start_next_trip.g.dart';

/// Where a start came from, for M15's analytics, and where the card's close
/// lands (M10 adds the apartment, contracts/apartment.md "The goal view").
enum StartFrom { home, result, lines, apartment }

/// The fuel sheet (M12's; a placeholder until then).
const fuelSheetLocation = '/shop/fuel';

/// Whether [tripId] skips the pre-trip card: by default the card setting
/// and what the player has met ([skipPreTripCard]).
typedef CardSkip = bool Function(WidgetRef ref, String tripId);

/// Whether a start is waiting at the checkpoint: a second tap meanwhile,
/// from Home or the result, does nothing (M11's interstitial shows once).
@Riverpod(keepAlive: true)
class StartUnderWay extends _$StartUnderWay {
  @override
  bool build() => false;

  void begin() => state = true;

  void end() => state = false;
}

/// Starts [tripId] as contracts/home.md says. Returns whether it navigated.
Future<bool> startNextTrip(
  BuildContext context,
  WidgetRef ref, {
  required String tripId,
  required StartFrom from,
  CardSkip skipCard = skipPreTripCard,
}) async {
  // 0. A trip that may not start goes nowhere (specs/014-m09-lines-vehicles
  // FR-012): every screen offers only playable trips, so this is a guard.
  final content = ref.read(contentSourceProvider);
  final trip = content.trip(tripId);
  if (trip == null ||
      !tripPlayable(content, ref.read(playerProgressProvider), tripId)) {
    return false;
  }
  if (ref.read(startUnderWayProvider)) return false;
  // 1. An empty tank, unless M07's fuel lesson is about to fill it.
  final fuel = homeFuelState(
    ref.read(economyViewProvider).fuel,
    lessonDue: ref.read(firstSessionProvider).fuelLessonDue(tripId),
  );
  if (fuel == HomeFuelState.empty) {
    return NavGuard.go(context, fuelSheetLocation);
  }
  // 2. Between trips: M11's interstitial, when it has one.
  final underWay = ref.read(startUnderWayProvider.notifier)..begin();
  try {
    await ref.read(betweenTripsCheckpointProvider).pass();
  } finally {
    underWay.end();
  }
  if (!context.mounted) return false;
  // 3. A tutorial trip, or a trip with nothing to brief, starts at once;
  // M07's redirects on /trip/<id> still apply. The session as it is now,
  // after the wait.
  final session = ref.read(firstSessionProvider);
  final tutorial =
      session.inFirstSession && session.facts.tutorialTrips.contains(tripId);
  if (tutorial || skipCard(ref, tripId)) {
    return NavGuard.go(context, '/trip/$tripId');
  }
  // The card opens where the start came from, so its close lands there:
  // under the line's details from Lines (research R5).
  return NavGuard.go(context, switch (from) {
    StartFrom.home || StartFrom.result => '/home/pre-trip/$tripId',
    StartFrom.lines =>
      '/lines/${toGlossaryLine(trip.lineId).wireName}/pre-trip/$tripId',
    StartFrom.apartment => '/apartment/pre-trip/$tripId',
  });
}
