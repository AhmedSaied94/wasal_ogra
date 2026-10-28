import 'package:content_models/content_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/account/account_providers.dart';
import 'package:wassal/core/account/domain/account.dart';
import 'package:wassal/core/content/pack_content_source.dart';
import 'package:wassal/core/economy/domain/economy_state.dart';
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/core/routing/new_dot_providers.dart';
import 'package:wassal/core/routing/routes.dart';
import 'package:wassal/core/theme/components/app_icon.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
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

// `C-Home` as the board draws it: أحمد at level 3, 1,240 JENEHAT, 85 BONAT
// and 4 of 5 liters with 12:30 to the next; trip 12 of 30 on خط الجامعة
// with 27 of 90 stars; saving for «الأنتريه» at 3,200 in chapter 4; the
// apartment tab's dot. The daily row (M13), its event circle and the
// morning piggy (M11) are fakes in their slots, at the board's sizes.

/// The board's line: 30 trips, ending at «الجامعة».
const _trips = 30;

/// Trips 1 to 11 finished, 27 stars between them.
const _finished = 11;

Map<String, Object?> cHomePackJson() {
  final json = sampleJsonCopy();
  final gamaa = entry(json, 'lines', 'line_id', 'line_gamaa');
  final stations = (gamaa['stations']! as List<Object?>)
      .cast<Map<String, Object?>>();
  stations.last['name'] = {'ar-EG': 'الجامعة'};
  final template = entry(json, 'trips', 'trip_id', 'line_gamaa.01');
  json['trips'] = [
    for (final trip in entries(json, 'trips'))
      if (trip['line_id'] != 'line_gamaa') trip,
    for (var n = 1; n <= _trips; n++)
      {...template, 'trip_id': 'line_gamaa.${n.toString().padLeft(2, '0')}'},
  ];
  entry(json, 'items', 'item_id', 'salon.nish')['name'] = {'ar-EG': 'الأنتريه'};
  final catalog = json['catalog']! as Map<String, Object?>;
  for (final price in entries(catalog, 'prices')) {
    if (price['sku_id'] == 'salon.nish') price['amount'] = 3200;
  }
  return json;
}

/// Ch1's line done, the old microbus and the shabka owned: chapter 4, the
/// apartment open. Trips 1 to 11 of خط الجامعة: five at three stars and
/// six at two, the 11th the last finished.
EconomyState cHomeState(int nowMs) {
  TripProgress done(int stars, int at) =>
      TripProgress(bestStars: stars, plays: 1, firstCompletedAtMs: at);
  return EconomyState.newPlayer(fuelMax: 5, nowMs: nowMs).copyWith(
    jenehat: 1240,
    bonat: 85,
    // 12:30 to the next liter, at 20 minutes a liter.
    fuel: FuelState(liters: 4, countedFromMs: nowMs - 450000),
    displayName: () => 'أحمد',
    ownership: {
      microOld: Owned(kind: SkuKind.vehicle, acquiredAtMs: 0),
      shabka: Owned(kind: SkuKind.chapter, acquiredAtMs: 0),
    },
    progress: {
      'line_hay.01': done(3, 1),
      'line_hay.02': done(3, 2),
      for (var n = 1; n <= _finished; n++)
        'line_gamaa.${n.toString().padLeft(2, '0')}': done(
          n <= 5 ? 3 : 2,
          10 + n,
        ),
    },
  );
}

/// Pumps الموقف as `C-Home` draws it, on [size] (the board's frame by
/// default) at [textScale]. [editPack] and [editState] change the board's
/// pack and player for the boards drawn over Home, and [overrides] fill
/// their slots.
Future<ProviderContainer> pumpCHome(
  WidgetTester tester, {
  DigitStyle digits = DigitStyle.arabicIndic,
  Size? size,
  double textScale = 1.0,
  void Function(Map<String, Object?> json)? editPack,
  EconomyState Function(EconomyState state)? editState,
  List<Override> overrides = const [],
}) async {
  final json = cHomePackJson();
  editPack?.call(json);
  final economy = await testEconomy(
    content: PackContentSource(Pack.fromJson(json)),
    firstState: (nowMs) {
      final state = cHomeState(nowMs);
      return editState == null ? state : editState(state);
    },
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
    // The fuel pill's countdown ticks: nothing settles.
    settle: false,
    settleBoot: false,
    overrides: [
      profileProvider.overrideWithValue(
        Profile(
          playerId: playerIdOf(1),
          providers: const {},
          displayName: 'أحمد',
          driverLevel: 3,
        ),
      ),
      homeDailyRowProvider.overrideWithValue((_) => const _DailyRow()),
      morningPiggySlotProvider.overrideWithValue((_) => const BoardPiggy()),
      ...overrides,
    ],
  );
  if (size == null) {
    applyDesignSurface(tester, const Size(390, 844), topInset: designTopInset);
  } else {
    applySurfaceSize(tester, size);
  }
  container.read(newDotProvider(Section.apartment).notifier).show();
  await pumpFrames(tester);
  return container;
}

/// M13's daily row as the board draws it: the gift, the tasks, the
/// challenge and the Ramadan event, 58 wide, 6 apart.
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
        label: 'مهام اليوم، خلصت ٢ من ٣',
        icon: 'tasks',
        caption: 'المهام',
        badge: '٢/٣',
      ),
      BoardDailyCircle(
        label: 'تحدي اليوم، فيه جديد',
        icon: 'challenge_trophy',
        caption: 'التحدي',
        dot: true,
      ),
      BoardDailyCircle(
        label: 'مناسبة رمضان',
        icon: 'lantern',
        caption: 'رمضان',
        event: true,
      ),
    ],
  );
}

class BoardDailyCircle extends StatelessWidget {
  const BoardDailyCircle({
    required this.label,
    required this.icon,
    required this.caption,
    this.dot = false,
    this.badge,
    this.event = false,
    this.offline = false,
    super.key,
  });

  final String label;
  final String icon;
  final String caption;
  final bool dot;
  final String? badge;
  final bool event;

  /// Needs the network: dimmed, and no control (`HomeStates` box 30).
  final bool offline;

  /// `HomeStates` draws an offline circle at 0.55.
  static const double _offlineOpacity = 0.55;

  static const double _width = 58;
  static const double _height = 65;
  static const double _circle = 46;
  static const double _icon = 26;
  static const double _dot = 12;
  static const double _captionTop = 49;

  @override
  Widget build(BuildContext context) => Semantics(
    button: !offline,
    label: label,
    excludeSemantics: true,
    child: GestureDetector(
      onTap: offline ? null : () {},
      child: Opacity(
        opacity: offline ? _offlineOpacity : 1,
        child: SizedBox(
          width: _width,
          height: _height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Align(
                alignment: Alignment.topCenter,
                child: Container(
                  width: _circle,
                  height: _circle,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: event
                        ? StationColors.all.first.bg
                        : ColorTokens.paper,
                    shape: BoxShape.circle,
                    boxShadow: const [LipTokens.chip],
                  ),
                  child: AppIcon(icon, size: _icon),
                ),
              ),
              PositionedDirectional(
                top: _captionTop,
                start: 0,
                end: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: SpaceTokens.s4,
                    ),
                    decoration: BoxDecoration(
                      color: ColorTokens.paper,
                      borderRadius: BorderRadius.circular(RadiusTokens.pill),
                    ),
                    // One line, wider than the circle when it must
                    // («محتاج نت», `HomeStates` box 33).
                    child: Text(
                      caption,
                      softWrap: false,
                      overflow: TextOverflow.visible,
                      style: TypeTokens.label.copyWith(color: ColorTokens.ink),
                    ),
                  ),
                ),
              ),
              if (dot)
                PositionedDirectional(
                  top: 0,
                  end: SpaceTokens.s4,
                  child: Container(
                    width: _dot,
                    height: _dot,
                    decoration: BoxDecoration(
                      color: ColorTokens.danger,
                      shape: BoxShape.circle,
                      border: Border.all(color: ColorTokens.ink, width: 2),
                    ),
                  ),
                ),
              if (badge case final badge?)
                PositionedDirectional(
                  top: -SpaceTokens.s4,
                  end: -SpaceTokens.s2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: SpaceTokens.s6,
                      vertical: SpaceTokens.s2,
                    ),
                    decoration: BoxDecoration(
                      color: ColorTokens.primary,
                      borderRadius: BorderRadius.circular(RadiusTokens.pill),
                    ),
                    child: Text(
                      badge,
                      style: TypeTokens.label.copyWith(
                        color: ColorTokens.paper,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// M11's morning piggy as the board draws it: one 52-high row.
class BoardPiggy extends StatelessWidget {
  const BoardPiggy({this.offline = false, super.key});

  /// Needs the network: «محتاج نت» on `paper` instead of «ببلاش», and no
  /// control (`HomeStates` boxes 56, 60).
  final bool offline;

  static const double _icon = 30;
  static const double _playIcon = 16;
  static const double _pillWidth = 82;
  static const double _pillHeight = 32;

  @override
  Widget build(BuildContext context) => Semantics(
    button: !offline,
    label: 'حصّالة الصبح',
    excludeSemantics: true,
    child: GestureDetector(
      onTap: offline ? null : () {},
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: SpaceTokens.s12),
        decoration: BoxDecoration(
          color: ColorTokens.sunSoft,
          borderRadius: BorderRadius.circular(RadiusTokens.bubble),
          boxShadow: const [LipTokens.sunSoft],
        ),
        child: Row(
          spacing: SpaceTokens.s10,
          children: [
            const AppIcon('piggy', size: _icon),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'حصّالة الصبح',
                    style: TypeTokens.row.copyWith(color: ColorTokens.ink),
                  ),
                  Text(
                    'اتفرج على إعلان وخد جنيهات وبونات',
                    style: TypeTokens.label.copyWith(color: ColorTokens.ink2),
                  ),
                ],
              ),
            ),
            if (offline)
              Container(
                height: _pillHeight,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(
                  horizontal: SpaceTokens.s12,
                ),
                decoration: BoxDecoration(
                  color: ColorTokens.paper,
                  borderRadius: BorderRadius.circular(RadiusTokens.pill),
                ),
                child: Text(
                  'محتاج نت',
                  style: TypeTokens.label
                      .weight(700)
                      .copyWith(color: ColorTokens.ink),
                ),
              )
            else
              Container(
                width: _pillWidth,
                height: _pillHeight,
                decoration: BoxDecoration(
                  color: ColorTokens.primary,
                  borderRadius: BorderRadius.circular(RadiusTokens.pill),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  spacing: SpaceTokens.s4,
                  children: [
                    Text(
                      'ببلاش',
                      style: TypeTokens.label.copyWith(
                        color: ColorTokens.paper,
                      ),
                    ),
                    const AppIcon('ad_play_on_primary', size: _playIcon),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
