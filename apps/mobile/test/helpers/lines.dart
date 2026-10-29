// Lines test helpers (specs/014-m09-lines-vehicles): the app on a pack and
// a scripted player, opened at a location.
import 'package:content_models/content_models.dart';
import 'package:drift/drift.dart' show ApplyInterceptor;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter/widgets.dart' show Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/content/pack_content_source.dart';
import 'package:wassal/core/economy/domain/economy_state.dart';
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/core/preferences/settings_store.dart';
import 'package:wassal/core/routing/router.dart';
import 'package:wassal/core/sync/server_status.dart';

import 'content.dart';
import 'economy.dart';
import 'pump_app.dart';
import 'surfaces.dart';
import 'synthetic_packs.dart';
import 'trip.dart';

/// A player's best stars at one play each, finished in the map's order.
Map<String, TripProgress> starsOf(Map<String, int> stars) => {
  for (final (i, MapEntry(:key, :value)) in stars.entries.indexed)
    key: TripProgress(bestStars: value, plays: 1, firstCompletedAtMs: i + 1),
};

/// Vehicles and chapters owned, by `(kind, sku id)`.
Map<OwnedKey, Owned> ownedOf(Set<(SkuKind, String)> owned) => {
  for (final key in owned) key: Owned(kind: key.$1, acquiredAtMs: 0),
};

/// A returning player with these balances, stars and ownership.
EconomyState Function(int nowMs) playerState({
  int jenehat = 0,
  int bonat = 0,
  Map<String, int> stars = const {},
  Set<(SkuKind, String)> owned = const {},
  int liters = 5,
}) =>
    (nowMs) => EconomyState.newPlayer(fuelMax: 5, nowMs: nowMs).copyWith(
      jenehat: jenehat,
      bonat: bonat,
      fuel: FuelState(liters: liters, countedFromMs: nowMs),
      progress: starsOf(stars),
      ownership: ownedOf(owned),
      // Named, so Home's arrival doesn't ask (M07).
      displayName: () => 'أحمد',
    );

/// The app on [pack] ([artboardLines] by default) for [state], at
/// [location], on [surface]'s frame or [size].
Future<(ProviderContainer, TestEconomy)> pumpLinesApp(
  WidgetTester tester, {
  Map<String, Object?>? pack,
  EconomyState Function(int nowMs)? state,
  String location = '/lines',
  ServerStatusState serverStatus = const ServerStatusState(),
  Surface surface = Surface.reference,
  Size? size,
  double textScale = 1.0,
  DigitStyle digits = DigitStyle.arabicIndic,
  SettingsStore? settingsStore,
  List<Override> overrides = const [],
  bool settle = true,
  bool newPlayer = false,
  FailingInterceptor? interceptor,
}) async {
  final json = pack ?? artboardLines();
  final economy = await testEconomy(
    content: PackContentSource(Pack.fromJson(json)),
    firstState: state ?? playerState(),
    executor: interceptor == null
        ? null
        : (inner) => inner.interceptWith(interceptor),
  );
  final container = await pumpWassalApp(
    tester,
    content: contentTestOverrides(
      assets: bundledAssetsFor(encodePackFile(json)),
    ),
    economy: economyOverridesOf(economy),
    serverStatus: serverStatus,
    surface: surface,
    size: size,
    textScale: textScale,
    digits: digits,
    settingsStore: settingsStore,
    overrides: overrides,
    settle: settle,
    newPlayer: newPlayer,
  );
  container.read(routerProvider).go(location);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }
  return (container, economy);
}

/// The router's location now.
String locationOf(ProviderContainer container) => container
    .read(routerProvider)
    .routerDelegate
    .currentConfiguration
    .uri
    .toString();

/// The sample pack, which has two lines and two vehicles.
Map<String, Object?> samplePackJsonForLines() => samplePackJson();
