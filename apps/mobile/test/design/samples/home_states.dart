import 'package:content_models/content_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/account/account_providers.dart';
import 'package:wassal/core/account/domain/account.dart';
import 'package:wassal/core/content/pack_content_source.dart';
import 'package:wassal/core/economy/domain/economy_state.dart';
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/core/sync/server_status.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/home/application/home_slots.dart';

import '../../helpers/account.dart';
import '../../helpers/content.dart';
import '../../helpers/economy.dart';
import '../../helpers/progress.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/surfaces.dart';
import '../../helpers/trip.dart';
import '../design_check.dart';
import 'c_home.dart';

// `HomeStates` as the board draws it: out of fuel, offline and chapter 2
// together. حمادة at level 1, 1,240 JENEHAT, 40 BONAT and 0 of 5 liters
// with 12:30 to the next; trip 8 of 20 on خط الحي with 14 of 60 stars, the
// tuktuk with بلية; chapter 2's goal, the old microbus at 2,000, with the
// apartment opening in chapter 4. The daily row (M13) and the morning
// piggy (M11) are fakes in their slots, offline as drawn.
//
// The board's chapter 2 can't hold with خط الحي unfinished: chapter 1's
// goal is that line. The sample meets chapter 1 with the tuktuk the player
// starts with instead.

/// The board's line: 20 trips, ending at «الحي».
const _trips = 20;

/// Trips 1 to 7 finished, two stars each.
const _finished = 7;

Map<String, Object?> homeStatesPackJson() {
  final json = sampleJsonCopy();
  final hay = entry(json, 'lines', 'line_id', 'line_hay');
  final stations = (hay['stations']! as List<Object?>)
      .cast<Map<String, Object?>>();
  stations.last['name'] = {'ar-EG': 'الحي'};
  final template = entry(json, 'trips', 'trip_id', 'line_hay.01');
  json['trips'] = [
    for (final trip in entries(json, 'trips'))
      if (trip['line_id'] != 'line_hay') trip,
    for (var n = 1; n <= _trips; n++)
      {...template, 'trip_id': 'line_hay.${n.toString().padLeft(2, '0')}'},
  ];
  entry(json, 'chapters', 'chapter_id', 'ch1_first_job')['goal'] = {
    'kind': 'own_vehicle',
    'vehicle_id': 'tuktuk',
  };
  final catalog = json['catalog']! as Map<String, Object?>;
  for (final price in entries(catalog, 'prices')) {
    if (price['sku_id'] == 'micro_old') price['amount'] = 2000;
  }
  return json;
}

EconomyState homeStatesState(int nowMs) =>
    EconomyState.newPlayer(fuelMax: 5, nowMs: nowMs).copyWith(
      jenehat: 1240,
      bonat: 40,
      // 12:30 to the next liter, at 20 minutes a liter.
      fuel: FuelState(liters: 0, countedFromMs: nowMs - 450000),
      displayName: () => 'حمادة',
      progress: {
        for (var n = 1; n <= _finished; n++)
          'line_hay.${n.toString().padLeft(2, '0')}': TripProgress(
            bestStars: 2,
            plays: 1,
            firstCompletedAtMs: n,
          ),
      },
    );

/// Pumps الموقف as `HomeStates` draws it, on [size] (the board's frame by
/// default) at [textScale].
Future<ProviderContainer> pumpHomeStates(
  WidgetTester tester, {
  DigitStyle digits = DigitStyle.arabicIndic,
  Size? size,
  double textScale = 1.0,
}) async {
  final json = homeStatesPackJson();
  final economy = await testEconomy(
    content: PackContentSource(Pack.fromJson(json)),
    firstState: homeStatesState,
  );
  await preloadTripArt(tester);
  final container = await pumpWassalApp(
    tester,
    digits: digits,
    textScale: textScale,
    content: contentTestOverrides(
      assets: bundledAssetsFor(encodePackFile(json)),
    ),
    economy: economyOverridesOf(economy),
    serverStatus: const ServerStatusState(reach: Reach.offline),
    // The fuel countdown ticks: nothing settles.
    settle: false,
    settleBoot: false,
    overrides: [
      profileProvider.overrideWithValue(
        Profile(
          playerId: playerIdOf(1),
          providers: const {},
          displayName: 'حمادة',
          driverLevel: 1,
        ),
      ),
      homeDailyRowProvider.overrideWithValue((_) => const _DailyRow()),
      morningPiggySlotProvider.overrideWithValue(
        (_) => const BoardPiggy(offline: true),
      ),
    ],
  );
  if (size == null) {
    applyDesignSurface(tester, const Size(390, 844), topInset: designTopInset);
  } else {
    applySurfaceSize(tester, size);
  }
  // The banner comes in and the scene gives up its height.
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  return container;
}

/// M13's daily row offline, as the board draws it: the gift, the tasks,
/// and the challenge, which needs the network.
class _DailyRow extends StatelessWidget {
  const _DailyRow();

  @override
  Widget build(BuildContext context) => const Row(
    mainAxisSize: MainAxisSize.min,
    spacing: SpaceTokens.s6,
    children: [
      BoardDailyCircle(
        label: 'هدية اليوم، فيها جديد',
        icon: 'gift',
        caption: 'الهدية',
        dot: true,
      ),
      BoardDailyCircle(
        label: 'مهام اليوم، خلصت ١ من ٣',
        icon: 'tasks',
        caption: 'المهام',
        badge: '١/٣',
      ),
      BoardDailyCircle(
        label: 'تحدي اليوم، محتاج نت',
        icon: 'challenge_trophy',
        caption: 'محتاج نت',
        offline: true,
      ),
    ],
  );
}
