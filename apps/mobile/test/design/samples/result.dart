import 'package:content_models/content_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/core/content/pack_content_source.dart';
import 'package:wassal/core/economy/domain/economy_state.dart';
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/core/routing/router.dart';
import 'package:wassal/core/theme/components/app_icon.dart';
import 'package:wassal/core/theme/components/buttons.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/result/application/quote_provider.dart';
import 'package:wassal/features/result/application/result_slots.dart';
import 'package:wassal/features/result/domain/quote.dart';
import 'package:wassal/features/result/domain/result_args.dart';
import 'package:wassal/features/trip/domain/looks.dart';

import '../../helpers/economy.dart';
import '../../helpers/progress.dart';
import '../../helpers/trip.dart';
import '../design_check.dart';
import 'c_home.dart';
import 'pre_trip.dart';

// `Result` over `C-Home`: trip 12 of خط الجامعة, the PreTrip board's trip,
// finished at two stars, the student given half a pound too much; 78.5
// collected, 7 in tips, 85 JENEHAT paid. الحاجة's thanks is the quote. The
// pay took the balance from 1,240 to 1,325 of the 3,200 «الأنتريه». The
// task banner (M13, with its +5 BONAT) and the ×2 offer (M11) are fakes in
// their slots, at the board's sizes.

/// The board's frame: one tall surface.
const resultBoardSize = Size(390, 1100);

/// Trip 12's start.
final _start = txnIdOf(12);

/// The balance before the trip and its pay.
const _before = 1240;
const _pay = 85;

/// The board's quote, as the sample's thanks.
const _thanks = 'ربنا يكرمك يا ابني.. الباقي وصل';

void _boardPack(Map<String, Object?> json) {
  boardTrip12(json);
  final thanks = entry(json, 'speech_pools', 'speech_key', 'passenger.thanks');
  thanks['lines'] = [
    {
      'text': {'ar-EG': _thanks},
    },
  ];
}

/// The student of trip 12, the second rider.
String _studentOf(Map<String, Object?> json) {
  final riders =
      entry(json, 'trips', 'trip_id', 'line_gamaa.12')['passengers']!
          as List<Object?>;
  return (riders[1]! as Map<String, Object?>)['passenger_id']! as String;
}

/// Trip 12's result, as the trip hands it over.
ResultArgs boardResultArgs() {
  final json = cHomePackJson();
  _boardPack(json);
  final trip = PackContentSource(Pack.fromJson(json)).trip('line_gamaa.12')!;
  final params = loadFixture('sample__line_hay_01_three_stars').params;
  return ResultArgs(
    result: TripResult.fromJson({
      'boosters_used': <Object?>[],
      'caught_liars': 0,
      'command_log_hash': 'result-board',
      'duration_ms': 90000,
      'earnings_jenehat': _pay,
      'fares_collected_piasters': 7850,
      'fights': 0,
      'impatient': 0,
      'lost_fares': 0,
      'missed_stops': 0,
      'mistakes': [
        {
          'amount_piasters': 50,
          'kind': 'over',
          'passenger_id': _studentOf(json),
        },
      ],
      'outcome': 'finished',
      'overpaid_piasters': 50,
      'reputation': 100,
      'reputation_lost': <String, Object?>{},
      'rev': trip.rev,
      'revived': false,
      'star_flags': {'no_fights': true, 'no_mistakes': false, 'reached': true},
      'stars': 2,
      'tips_piasters': 700,
      'trip_id': 'line_gamaa.12',
    }),
    startTxn: _start,
    replay: ReplayRecord(
      definition: trip,
      seed: 1,
      params: params,
      commandLog: const [],
      tMs: 90000,
    ),
    bestStarsBefore: 0,
    jenehatBefore: _before,
  );
}

/// الحاجة's thanks, picked in place.
final _quote = Quote(
  passengerId: 'hagga',
  look: looks['hagga']!,
  labelKey: looks['hagga']!.labelKey,
  speechKey: 'passenger.thanks',
  variant: 0,
);

/// Pumps the result as `Result` draws it, on its tall frame, or on [size]
/// at [textScale]. Without [slots], the task and ×2 slots stay empty, as
/// this feature ships them; [doubled] doubles the pay, and without
/// [withQuote] there is no quote. [overrides] go last.
Future<ProviderContainer> pumpResult(
  WidgetTester tester, {
  DigitStyle digits = DigitStyle.arabicIndic,
  Size? size,
  double textScale = 1.0,
  bool slots = true,
  bool doubled = false,
  bool withQuote = true,
  List<Override> overrides = const [],
}) async {
  final container = await pumpCHome(
    tester,
    digits: digits,
    size: size,
    textScale: textScale,
    editPack: _boardPack,
    editState: (state) => state.copyWith(
      jenehat: _before + _pay,
      progress: {
        ...state.progress,
        'line_gamaa.12': const TripProgress(
          bestStars: 2,
          plays: 1,
          firstCompletedAtMs: 30,
        ),
      },
      lastResult: () => LastResult(
        startTxn: _start,
        outcome: TripOutcome.finished,
        earningsJenehat: _pay,
        doubled: doubled,
      ),
    ),
    overrides: [
      quoteRunnerProvider.overrideWithValue(
        (_) async => withQuote ? _quote : null,
      ),
      if (slots) ...[
        resultTaskSlotProvider.overrideWithValue((
          banner: (_) => const _TaskBanner(),
          bonat: 5,
        )),
        resultDoubleSlotProvider.overrideWithValue(
          (_, _) => const _DoubleOffer(),
        ),
      ],
      ...overrides,
    ],
  );
  if (size == null) {
    applyDesignSurface(tester, resultBoardSize, topInset: designTopInset);
  }
  container
      .read(routerProvider)
      .go('/trip/line_gamaa.12/result', extra: boardResultArgs());
  // The page fades in, the pay counts up, then the bar fills.
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return container;
}

/// M13's banner as the board draws it: «مهمة خلصت: …» with its BONAT.
class _TaskBanner extends StatelessWidget {
  const _TaskBanner();

  static const double _height = 40;
  static const double _icon = 20;

  @override
  Widget build(BuildContext context) => Container(
    height: _height,
    padding: const EdgeInsets.symmetric(horizontal: SpaceTokens.s12),
    decoration: BoxDecoration(
      color: ColorTokens.primarySoft,
      borderRadius: BorderRadius.circular(RadiusTokens.pill),
    ),
    child: Row(
      spacing: SpaceTokens.s8,
      children: [
        const AppIcon('tasks', size: _icon, color: ColorTokens.primary),
        Expanded(
          child: Text(
            'مهمة خلصت: رجّع ٢٠ باقي صح',
            style: TypeTokens.label.copyWith(color: ColorTokens.ink),
          ),
        ),
        Text(
          '+٥ بونات',
          style: TypeTokens.label.copyWith(color: ColorTokens.primary),
        ),
      ],
    ),
  );
}

/// M11's offer as the board draws it: «اقبض ×٢», 70 high, and the decline
/// link under it, drawn 36 high (M11's takes 44 to the touch).
class _DoubleOffer extends StatelessWidget {
  const _DoubleOffer();

  static const double _height = 70;
  static const double _link = 36;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: SpaceTokens.s12,
    children: [
      AppButton.primary(
        label: 'اقبض ×٢',
        height: _height,
        semanticLabel: 'اقبض ×٢',
        onTap: () {},
      ),
      Semantics(
        button: true,
        label: 'لأ، خد ٨٥ بس',
        excludeSemantics: true,
        child: GestureDetector(
          onTap: () {},
          child: SizedBox(
            height: _link,
            child: Center(
              child: Text(
                'لأ، خد ٨٥ بس',
                style: TypeTokens.label.copyWith(color: ColorTokens.inkMuted),
              ),
            ),
          ),
        ),
      ),
    ],
  );
}
