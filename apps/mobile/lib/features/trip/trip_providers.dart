// The trip screen's providers (contracts/trip-controller.md "Providers").
import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:rive/rive.dart' as rive;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wassal/bootstrap/startup.dart';
import 'package:wassal/core/config/config_providers.dart';
import 'package:wassal/core/content/content_providers.dart';
import 'package:wassal/core/economy/economy_providers.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/features/trip/application/trip_ad_offers.dart';
import 'package:wassal/features/trip/application/trip_controller.dart';
import 'package:wassal/features/trip/application/trip_settings.dart';
import 'package:wassal/features/trip/data/drift_trip_records.dart';
import 'package:wassal/features/trip/data/trip_records.dart';
import 'package:wassal/features/trip/presentation/scene/passenger_art.dart';
import 'package:wassal/features/trip/presentation/scene/rive_passenger_art.dart';
import 'package:wassal/features/trip/presentation/trip_text.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

part 'trip_providers.g.dart';

/// The only writer of the trip's tables, over the database startup opened.
@Riverpod(keepAlive: true)
TripRecords tripRecords(Ref ref) =>
    DriftTripRecords(ref.watch(appDatabaseProvider).requireValue);

/// Sound, vibration and the hints already seen, kept on the device.
@Riverpod(keepAlive: true)
class TripSettingsNotifier extends _$TripSettingsNotifier {
  @override
  TripSettings build() =>
      TripSettings.read(ref.watch(settingsStoreProvider).requireValue);

  /// The current settings, for code outside the widget tree.
  TripSettings get current => state;

  Future<void> setSound({required bool on}) =>
      _save(state.copyWith(soundOn: on));

  Future<void> setHaptics({required bool on}) =>
      _save(state.copyWith(hapticsOn: on));

  /// Remembers that بلية explained [archetypeWire].
  Future<void> markHintSeen(String archetypeWire) =>
      _save(state.copyWith(hintsSeen: {...state.hintsSeen, archetypeWire}));

  Future<void> _save(TripSettings next) async {
    if (next == state) return;
    state = next;
    await next.write(ref.read(settingsStoreProvider).requireValue);
  }
}

/// M11 fills this in.
@Riverpod(keepAlive: true)
TripAdOffers tripAdOffers(Ref ref) => const NoTripAdOffers();

/// Whether the screen's frames drive the trip's clock. Widget tests and
/// goldens turn it off and move the clock themselves.
@Riverpod(keepAlive: true)
bool tripFrameDriven(Ref ref) => true;

/// The owner's character file, decoded once; null without it (T060).
@Riverpod(keepAlive: true)
Future<rive.File?> passengerRive(Ref ref) async {
  final file = await loadPassengerRive();
  ref.onDispose(() => file?.dispose());
  return file;
}

/// How passengers are drawn: the character once its file loads, else the
/// stand-in.
@Riverpod(keepAlive: true)
PassengerArtFactory passengerArt(Ref ref) =>
    switch (ref.watch(passengerRiveProvider).value) {
      final file? => RivePassengerArtFactory(file),
      null => const StandInPassengerArtFactory(),
    };

/// A trip that opens from a fixture instead of the pack: the scripted
/// player's seam (contracts/trip-controller.md "Test seams").
@Riverpod(keepAlive: true)
FixedTrip? tripFixed(Ref ref) => null;

/// The controller of the trip screen showing [tripId]: made and opened
/// when the screen opens, disposed with it.
@riverpod
TripController tripController(Ref ref, String tripId) {
  // Read once: nothing below may change during a trip (the pack switches
  // only at launch or at Home), and the controller outlives no screen.
  final content = ref.read(contentSourceProvider);
  final version = ref.read(contentVersionProvider);
  final config = ref.read(configSourceProvider);
  final numbers = ref.read(numberFormatterProvider);
  final settings = ref.read(tripSettingsProvider.notifier);
  final letters = lookupAppLocalizations(const Locale('ar'));
  final controller = TripController(
    economy: ref.read(economyProvider).requireValue,
    content: () => content,
    contentVersion: () => version,
    config: () => config,
    records: ref.read(tripRecordsProvider),
    piasters: numbers.piasters,
    stationLetter: letters.stationLetter,
    hintsSeen: () => settings.current.hintsSeen,
    onHintSeen: (wire) => unawaited(settings.markHintSeen(wire)),
    ads: ref.read(tripAdOffersProvider),
    fixedTrip: ref.read(tripFixedProvider),
  );
  ref.onDispose(controller.dispose);
  unawaited(controller.open(tripId));
  return controller;
}
