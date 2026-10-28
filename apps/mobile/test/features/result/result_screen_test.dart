import 'dart:convert';

import 'package:content_models/content_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/bootstrap/app.dart' show appLocale;
import 'package:wassal/core/audio_haptics/sfx.dart';
import 'package:wassal/core/content/pack_content_source.dart';
import 'package:wassal/core/economy/domain/economy_state.dart';
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/core/l10n/number_formatter.dart';
import 'package:wassal/core/routing/router.dart';
import 'package:wassal/features/home/application/home_model.dart';
import 'package:wassal/features/home/application/last_finished_trip.dart';
import 'package:wassal/features/home/domain/savings_target.dart';
import 'package:wassal/features/onboarding/onboarding_providers.dart';
import 'package:wassal/features/onboarding/presentation/first_session_continue.dart';
import 'package:wassal/features/pre_trip/presentation/pre_trip_card.dart';
import 'package:wassal/features/result/application/quote_provider.dart';
import 'package:wassal/features/result/application/result_model.dart';
import 'package:wassal/features/result/domain/quote.dart';
import 'package:wassal/features/result/domain/result_args.dart';
import 'package:wassal/features/result/presentation/apartment_card.dart';
import 'package:wassal/features/result/presentation/breakdown_card.dart';
import 'package:wassal/features/result/presentation/mistakes_card.dart';
import 'package:wassal/features/result/presentation/pay_block.dart';
import 'package:wassal/features/result/presentation/quote_card.dart';
import 'package:wassal/features/result/presentation/result_screen.dart';
import 'package:wassal/features/result/presentation/result_stars.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

import '../../design/samples/c_home.dart';
import '../../helpers/content.dart';
import '../../helpers/economy.dart';
import '../../helpers/first_session.dart';
import '../../helpers/home.dart';
import '../../helpers/progress.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/routing.dart';
import '../../helpers/trip.dart';
import '../../helpers/tutorial_content.dart';

// The result screen (specs/013-m08-home-result, contracts/result.md,
// FR-035–FR-047): every figure the trip's own (SC-004), the last result's
// pay without the hand-over, Home with nothing kept, «مشوار تاني» and M07's
// «كمّل», back, the first three stars, the apartment card, reduced motion,
// and the line Home follows.

const _numbers = NumberFormatter(DigitStyle.arabicIndic);

Map<String, Object?> _plain(Object? json) =>
    jsonDecode(jsonEncode(json)) as Map<String, Object?>;

/// [fixture]'s finished trip, as the trip hands it over.
ResultArgs _argsOf(
  ParityFixture fixture, {
  TripDefinition? definition,
  Map<String, Object?> result = const {},
  int bestStarsBefore = 0,
  int jenehatBefore = 0,
  int start = 1,
}) => ResultArgs(
  result: TripResult.fromJson({
    ..._plain(fixture.expectedResult.toJson()),
    ...result,
  }),
  startTxn: txnIdOf(start),
  replay: ReplayRecord(
    definition: definition ?? fixture.definition,
    seed: fixture.seed,
    params: fixture.params,
    commandLog: fixture.commandLog,
    tMs: fixture.expectedResult.durationMs,
  ),
  bestStarsBefore: bestStarsBefore,
  jenehatBefore: jenehatBefore,
);

/// The pay counts up, then the bar fills.
Future<void> _settle(WidgetTester tester) =>
    pumpFrames(tester, count: 30, step: const Duration(milliseconds: 100));

/// The app on [pack] with [state], at Home; then [tripId]'s result as the
/// trip opens it, with [args]. The quote is picked in place.
Future<ProviderContainer> _open(
  WidgetTester tester, {
  required String tripId,
  ResultArgs? args,
  Map<String, Object?>? pack,
  EconomyState Function(int nowMs)? state,
  FakeSfxPlayer? sfx,
  bool newPlayer = false,
  List<Override> overrides = const [],
  bool settle = true,
}) async {
  final json = pack ?? sampleJsonCopy();
  final economy = await testEconomy(
    content: PackContentSource(Pack.fromJson(json)),
    firstState: state,
  );
  final container = await pumpWassalApp(
    tester,
    initialLocation: '/home',
    content: contentTestOverrides(
      assets: bundledAssetsFor(encodePackFile(json)),
    ),
    economy: economyOverridesOf(economy),
    trip: tripTestOverrides(sfx: sfx),
    newPlayer: newPlayer,
    settle: false,
    overrides: [
      quoteRunnerProvider.overrideWithValue(
        (record) async => pickQuote(record),
      ),
      ...overrides,
    ],
  );
  await pumpFrames(tester);
  container.read(routerProvider).go('/trip/$tripId/result', extra: args);
  if (settle) await _settle(tester);
  return container;
}

String _semanticsOf(WidgetTester tester, Key key) =>
    tester.getSemantics(find.byKey(key)).label;

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(appLocale);
  });

  testWidgets('every finished fixture: each figure is the result\'s '
      '(SC-004)', (tester) async {
    final semantics = tester.ensureSemantics();
    final fixtures = [
      for (final name in allFixtureNames())
        if (loadFixture(name).expectedResult.outcome == TripOutcome.finished)
          (name, loadFixture(name)),
    ];
    // The stress trip isn't in the pack: its line gets it.
    final json = sampleJsonCopy();
    for (final (_, f) in fixtures) {
      if (sampleContent().trip(f.definition.tripId) == null) {
        (json['trips']! as List<Object?>).add(_plain(f.definition.toJson()));
      }
    }
    final container = await _open(
      tester,
      tripId: 'line_hay.01',
      pack: json,
      settle: false,
    );
    for (final (i, (name, f)) in fixtures.indexed) {
      final r = f.expectedResult;
      container.read(routerProvider).go('/home');
      await pumpFrames(tester, count: 2);
      container
          .read(routerProvider)
          // Each trip has its own start.
          .go('/trip/${r.tripId}/result', extra: _argsOf(f, start: i + 1));
      await _settle(tester);

      expect(
        _semanticsOf(tester, ResultStars.groupKey),
        l10n.resultA11yStars(r.stars),
        reason: name,
      );
      expect(
        _semanticsOf(tester, BreakdownCard.faresKey),
        l10n.resultA11yBreakdownRow(
          l10n.resultFares,
          _numbers.piasters(r.faresCollectedPiasters),
        ),
        reason: name,
      );
      expect(
        _semanticsOf(tester, BreakdownCard.tipsKey),
        l10n.resultA11yBreakdownRow(
          l10n.resultTips,
          l10n.resultPlus(_numbers.piasters(r.tipsPiasters)),
        ),
        reason: name,
      );
      expect(
        _semanticsOf(tester, BreakdownCard.overpaidKey),
        l10n.resultA11yBreakdownRow(
          l10n.resultOverpaid,
          l10n.resultMinus(_numbers.piasters(r.overpaidPiasters)),
        ),
        reason: name,
      );
      expect(
        _semanticsOf(tester, BreakdownCard.fightsKey),
        l10n.resultA11yCountRow(l10n.resultFights, _numbers.integer(r.fights)),
        reason: name,
      );
      expect(
        tester.widget<Text>(find.byKey(PayBlock.amountKey)).data,
        _numbers.integer(r.earningsJenehat),
        reason: name,
      );
      final lines =
          r.mistakes.length +
          [r.fights, r.missedStops, r.lostFares].where((n) => n > 0).length;
      expect(
        find.byType(MistakesCard),
        lines == 0 ? findsNothing : findsOneWidget,
        reason: name,
      );
      expect(
        find.byKey(MistakesCard.lineKey(lines - 1)),
        lines == 0 ? findsNothing : findsOneWidget,
        reason: name,
      );
      expect(find.byKey(MistakesCard.lineKey(lines)), findsNothing);
    }
    semantics.dispose();
  });

  group('the whole result', () {
    final hay = loadFixture('sample__line_hay_01_three_stars');

    testWidgets('header, title, stars, quote, breakdown and pay', (
      tester,
    ) async {
      await _open(tester, tripId: 'line_hay.01', args: _argsOf(hay));
      expect(shows('المشوار ١ · خط الحي'), findsOneWidget);
      expect(find.text('وصلنا الفرن!'), findsOneWidget);
      expect(find.byType(ResultStars), findsOneWidget);
      expect(find.byType(QuoteCard), findsOneWidget);
      expect(find.byKey(QuoteCard.lineKey), findsOneWidget);
      expect(find.byType(BreakdownCard), findsOneWidget);
      // Three stars, nothing went wrong.
      expect(find.byType(MistakesCard), findsNothing);
      expect(
        tester.widget<Text>(find.byKey(PayBlock.amountKey)).data,
        _numbers.integer(hay.expectedResult.earningsJenehat),
      );
    });

    testWidgets('the mistakes, opening and closing', (tester) async {
      final f = loadFixture('ending__one_star');
      await _open(tester, tripId: f.definition.tripId, args: _argsOf(f));
      expect(find.text('خناقة واحدة ضيّعت النجمتين'), findsOneWidget);
      expect(find.byKey(MistakesCard.lineKey(0)), findsOneWidget);
      await tester.ensureVisible(find.byKey(MistakesCard.summaryKey));
      await tester.tap(find.byKey(MistakesCard.summaryKey));
      await tester.pump();
      expect(find.byKey(MistakesCard.lineKey(0)), findsNothing);
    });

    testWidgets('a doubled pay when the last result is this start\'s', (
      tester,
    ) async {
      final args = _argsOf(hay);
      await _open(
        tester,
        tripId: 'line_hay.01',
        args: args,
        state: (nowMs) =>
            EconomyState.newPlayer(fuelMax: 5, nowMs: nowMs).copyWith(
              lastResult: () => LastResult(
                startTxn: args.startTxn,
                outcome: TripOutcome.finished,
                earningsJenehat: args.result.earningsJenehat,
                doubled: true,
              ),
            ),
      );
      expect(
        tester.widget<Text>(find.byKey(PayBlock.amountKey)).data,
        _numbers.integer(2 * args.result.earningsJenehat),
      );
    });
  });

  group('without the hand-over', () {
    EconomyState Function(int) withLast(LastResult? last) =>
        (nowMs) => EconomyState.newPlayer(
          fuelMax: 5,
          nowMs: nowMs,
        ).copyWith(lastResult: () => last);

    testWidgets('the last result\'s pay only', (tester) async {
      await _open(
        tester,
        tripId: 'line_hay.01',
        state: withLast(
          LastResult(
            startTxn: txnIdOf(3),
            outcome: TripOutcome.finished,
            earningsJenehat: 85,
          ),
        ),
      );
      expect(currentLocation(tester), '/trip/line_hay.01/result');
      expect(find.text('وصلنا الفرن!'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(PayBlock.amountKey)).data,
        _numbers.integer(85),
      );
      for (final hidden in [
        ResultStars,
        QuoteCard,
        BreakdownCard,
        MistakesCard,
      ]) {
        expect(find.byType(hidden), findsNothing, reason: '$hidden');
      }
      // No gain marked.
      expect(tester.getSize(find.byKey(ApartmentCard.gainKey)).width, 0);
    });

    testWidgets('nothing kept: Home', (tester) async {
      await _open(tester, tripId: 'line_hay.01', state: withLast(null));
      expect(currentLocation(tester), '/home');
    });

    testWidgets('not a finished trip: Home', (tester) async {
      await _open(
        tester,
        tripId: 'line_hay.01',
        state: withLast(
          LastResult(
            startTxn: txnIdOf(3),
            outcome: TripOutcome.abandoned,
            earningsJenehat: 0,
          ),
        ),
      );
      expect(currentLocation(tester), '/home');
    });
  });

  group('«مشوار تاني»', () {
    final hay = loadFixture('sample__line_hay_01_three_stars');
    EconomyState Function(int) played({int liters = 5}) =>
        (nowMs) => EconomyState.newPlayer(fuelMax: 5, nowMs: nowMs).copyWith(
          fuel: FuelState(liters: liters, countedFromMs: nowMs),
          progress: const {
            'line_hay.01': TripProgress(
              bestStars: 3,
              plays: 1,
              firstCompletedAtMs: 1,
            ),
          },
        );

    testWidgets('with fuel: the next trip\'s card', (tester) async {
      await _open(
        tester,
        tripId: 'line_hay.01',
        args: _argsOf(hay),
        state: played(),
      );
      expect(find.byKey(FirstSessionContinue.buttonKey), findsNothing);
      await tester.ensureVisible(find.byKey(ResultScreen.againKey));
      await tester.tap(find.byKey(ResultScreen.againKey));
      await _settle(tester);
      expect(currentLocation(tester), '/home/pre-trip/line_hay.02');
      expect(find.byType(PreTripCard), findsOneWidget);
    });

    testWidgets('on an empty tank: the fuel sheet', (tester) async {
      await _open(
        tester,
        tripId: 'line_hay.01',
        args: _argsOf(hay),
        state: played(liters: 0),
        settle: false,
      );
      await pumpFrames(tester);
      await tester.ensureVisible(find.byKey(ResultScreen.againKey));
      await tester.tap(find.byKey(ResultScreen.againKey));
      await pumpFrames(tester);
      expect(currentLocation(tester), '/shop/fuel');
    });

    testWidgets('its label says it spends a liter', (tester) async {
      final semantics = tester.ensureSemantics();
      await _open(
        tester,
        tripId: 'line_hay.01',
        args: _argsOf(hay),
        state: played(),
      );
      await tester.ensureVisible(find.byKey(ResultScreen.againKey));
      expect(
        _semanticsOf(tester, ResultScreen.againKey),
        contains(l10n.resultA11yAgain),
      );
      expect(
        find.text(l10n.resultAgainFuel(_numbers.integer(1))),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('M07\'s «كمّل» in its place in the first session', (
      tester,
    ) async {
      final trip = tutorialTrip('line_hay.02');
      await _open(
        tester,
        tripId: 'line_hay.02',
        args: _argsOf(
          hay,
          definition: trip,
          result: {'trip_id': 'line_hay.02'},
        ),
        pack: tutorialPackJson(),
        // The first two tutorial trips played, the third not yet.
        state: (nowMs) => played()(nowMs).copyWith(
          progress: const {
            'line_hay.01': TripProgress(
              bestStars: 3,
              plays: 1,
              firstCompletedAtMs: 1,
            ),
            'line_hay.02': TripProgress(
              bestStars: 3,
              plays: 1,
              firstCompletedAtMs: 2,
            ),
          },
        ),
        newPlayer: true,
        overrides: seededFirstSession((store) async {
          await store.markOpeningDone(0);
          await store.reachStep(2);
        }),
      );
      expect(find.byKey(FirstSessionContinue.buttonKey), findsOneWidget);
      expect(find.byKey(ResultScreen.againKey), findsNothing);
    });

    testWidgets('and once after the trip that ended the tutorial', (
      tester,
    ) async {
      final container = await _open(
        tester,
        tripId: 'line_hay.01',
        args: _argsOf(hay),
        state: played(),
        settle: false,
      );
      container.read(tutorialEndedOnProvider.notifier).tripId = 'line_hay.01';
      await _settle(tester);
      expect(find.byKey(FirstSessionContinue.buttonKey), findsOneWidget);
      expect(find.byKey(ResultScreen.againKey), findsNothing);
    });
  });

  group('back', () {
    final hay = loadFixture('sample__line_hay_01_three_stars');

    testWidgets('the back button goes Home', (tester) async {
      await _open(tester, tripId: 'line_hay.01', args: _argsOf(hay));
      await tester.tap(find.byKey(ResultScreen.backKey));
      await _settle(tester);
      expect(currentLocation(tester), '/home');
    });

    testWidgets('so does the system back', (tester) async {
      await _open(tester, tripId: 'line_hay.01', args: _argsOf(hay));
      await pressBack(tester);
      await _settle(tester);
      expect(currentLocation(tester), '/home');
    });
  });

  group('a first three stars', () {
    final hay = loadFixture('sample__line_hay_01_three_stars');

    testWidgets('«رقم قياسي جديد» and the horn, once', (tester) async {
      final sfx = FakeSfxPlayer();
      await _open(
        tester,
        tripId: 'line_hay.01',
        args: _argsOf(hay, bestStarsBefore: 2),
        sfx: sfx,
      );
      expect(find.text('رقم قياسي جديد'), findsOneWidget);
      expect(find.byKey(ResultScreen.confettiKey), findsOneWidget);
      expect(sfx.played, [Sfx.horn]);
    });

    testWidgets('not when it had three already', (tester) async {
      final sfx = FakeSfxPlayer();
      await _open(
        tester,
        tripId: 'line_hay.01',
        args: _argsOf(hay, bestStarsBefore: 3),
        sfx: sfx,
      );
      expect(find.byKey(ResultScreen.recordKey), findsNothing);
      expect(find.byKey(ResultScreen.confettiKey), findsNothing);
      expect(sfx.played, isEmpty);
    });
  });

  group('the apartment card (FR-043)', () {
    final hay = loadFixture('sample__line_hay_01_three_stars');

    /// The C-Home player, [jenehat] after a pay of [pay].
    Future<ProviderContainer> openApartment(
      WidgetTester tester, {
      required int jenehat,
      int pay = 85,
      bool args = true,
    }) => _open(
      tester,
      tripId: 'line_hay.01',
      args: args ? _argsOf(hay, jenehatBefore: jenehat - pay) : null,
      pack: cHomePackJson(),
      state: (nowMs) => cHomeState(nowMs).copyWith(
        jenehat: jenehat,
        fuel: FuelState(liters: 5, countedFromMs: nowMs),
        lastResult: () => LastResult(
          startTxn: txnIdOf(1),
          outcome: TripOutcome.finished,
          earningsJenehat: pay,
        ),
      ),
    );

    testWidgets('Home\'s target; the bar from before to now, the gain '
        'marked; what is missing', (tester) async {
      final container = await openApartment(tester, jenehat: 1240);
      final model = container.read(
        resultModelProvider('line_hay.01', _argsOf(hay, jenehatBefore: 1155)),
      ) as FullResult;
      expect(model.apartment.target, container.read(homeModelProvider).savings);
      expect(model.apartment.target, isA<ApartmentPieceTarget>());
      expect(find.text('الأنتريه'), findsOneWidget);
      expect(shows('فاضلك ١٬٩٦٠ ج'), findsOneWidget);
      final bar = tester.getSize(find.byKey(ApartmentCard.barKey)).width;
      expect(
        tester.getSize(find.byKey(ApartmentCard.fillKey)).width,
        closeTo(bar * 1240 / 3200, 0.5),
      );
      expect(
        tester.getSize(find.byKey(ApartmentCard.gainKey)).width,
        closeTo(bar * 85 / 3200, 0.5),
      );
    });

    testWidgets('the pay made it affordable: «تقدر تشتري …!»', (tester) async {
      await openApartment(tester, jenehat: 3250);
      expect(find.text('تقدر تشتري الأنتريه!'), findsOneWidget);
    });

    testWidgets('before the apartment opens: the chapter\'s goal', (
      tester,
    ) async {
      await _open(tester, tripId: 'line_hay.01', args: _argsOf(hay));
      expect(shows('خلّص خط الحي'), findsOneWidget);
    });

    testWidgets('a tap opens the apartment', (tester) async {
      await openApartment(tester, jenehat: 1240);
      await tester.ensureVisible(find.byType(ApartmentCard));
      await tester.tap(find.byType(ApartmentCard));
      await _settle(tester);
      expect(currentLocation(tester), '/apartment');
    });
  });

  testWidgets('reduced motion: final values at once, no confetti', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final hay = loadFixture('sample__line_hay_01_three_stars');
    await _open(
      tester,
      tripId: 'line_hay.01',
      args: _argsOf(hay, bestStarsBefore: 2),
      settle: false,
    );
    await tester.pump();
    await tester.pump();
    expect(
      tester.widget<Text>(find.byKey(PayBlock.amountKey)).data,
      _numbers.integer(hay.expectedResult.earningsJenehat),
    );
    expect(find.text('رقم قياسي جديد'), findsOneWidget);
    expect(find.byKey(ResultScreen.confettiKey), findsNothing);
  });

  testWidgets('Home follows the line of the result it opened', (tester) async {
    final f = loadFixture('ending__two_stars');
    final container = await _open(
      tester,
      tripId: f.definition.tripId,
      args: _argsOf(f),
    );
    expect(container.read(lastFinishedTripProvider), f.definition.tripId);
  });
}
