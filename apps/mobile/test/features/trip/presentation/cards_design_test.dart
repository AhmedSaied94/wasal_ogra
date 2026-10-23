import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/core/l10n/number_formatter.dart';
import 'package:wassal/core/theme/components/app_icon.dart';
import 'package:wassal/core/theme/components/buttons.dart';
import 'package:wassal/core/theme/components/controls.dart';
import 'package:wassal/core/theme/components/overlays.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/trip/application/trip_controller.dart';
import 'package:wassal/features/trip/application/trip_phase.dart';
import 'package:wassal/features/trip/application/trip_settings.dart';
import 'package:wassal/features/trip/domain/step_accumulator.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';
import 'package:wassal/features/trip/presentation/cards/booster_card.dart';
import 'package:wassal/features/trip/presentation/cards/dispute_card.dart';
import 'package:wassal/features/trip/presentation/cards/failure_card.dart';
import 'package:wassal/features/trip/presentation/cards/no_fuel_card.dart';
import 'package:wassal/features/trip/presentation/cards/pause_card.dart';
import 'package:wassal/features/trip/presentation/cards/retry_card.dart';
import 'package:wassal/features/trip/presentation/cards/trip_card.dart';
import 'package:wassal/features/trip/presentation/dashboard/dashboard.dart';
import 'package:wassal/features/trip/presentation/trip_text.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

import '../../../design/samples/c_trip.dart';
import '../../../design/samples/fail.dart';
import '../../../helpers/memory_settings_store.dart';
import '../../../helpers/routing.dart';
import '../../../helpers/trip.dart';

// Pausing and failing in the new look (tasks.md T088, spec FR-027 –
// FR-029, research R13): `Pause`, `Fail` and M02's other cards as the
// design's dialogs, with M02's behaviour. `pause_card_test.dart` and
// `failure_card_test.dart` keep M02's assertions.

const _numbers = NumberFormatter(DigitStyle.arabicIndic);

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(TripDashboard)));

Finder _in(Type card, Finder finder) =>
    find.descendant(of: find.byType(card), matching: finder);

/// The card's dialog: [card] sits in an [AppDialog].
void _expectDialog(WidgetTester tester, Finder inCard) => expect(
  find.ancestor(of: inCard, matching: find.byType(AppDialog)),
  findsOneWidget,
);

/// Shows [model] over `C-Trip`'s cabin.
Future<void> _show(WidgetTester tester, TripModel model) async {
  controllerOf(tester).debugShowModel(model);
  await tester.pumpAndSettle();
}

void main() {
  group('Pause', () {
    testWidgets('the title, its line, and the 60 pt «كمّل المشوار»', (
      tester,
    ) async {
      await pumpTrip(tester);
      await pressBack(tester);
      final l10n = _l10n(tester);
      _expectDialog(tester, find.byKey(PauseCard.resumeKey));
      expect(_in(PauseCard, find.text(l10n.pauseTitle)), findsOneWidget);
      expect(_in(PauseCard, find.text(l10n.pauseSubtitle)), findsOneWidget);
      expect(tester.getSize(find.byKey(PauseCard.resumeKey)).height, 60);
      expect(
        find.descendant(
          of: find.byKey(PauseCard.resumeKey),
          matching: find.text(l10n.pauseResume),
        ),
        findsOneWidget,
      );
      final home = tester.widget<AppButton>(find.byKey(PauseCard.homeKey));
      expect(home.label, l10n.pauseHome);
    });

    testWidgets('«عيد المشوار» carries the fuel chip, never «لتر»', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpTrip(tester);
      await pressBack(tester);
      final l10n = _l10n(tester);
      final chip = find.descendant(
        of: find.byKey(PauseCard.restartKey),
        matching: find.byType(CostChip),
      );
      expect(chip, findsOneWidget);
      expect(
        tester.widget<CostChip>(chip).amount,
        l10n.tripFuelChip(_numbers.integer(1)),
      );
      final pill = tester.widget<DecoratedBox>(
        find.descendant(of: chip, matching: find.byType(DecoratedBox)).first,
      );
      expect((pill.decoration as BoxDecoration).color, ColorTokens.sun);
      expect(
        find.descendant(
          of: chip,
          matching: find.byWidgetPredicate(
            (w) => w is AppIcon && w.name == 'fuel_small',
          ),
        ),
        findsOneWidget,
      );
      expect(_in(PauseCard, find.textContaining('لتر')), findsNothing);
      expect(
        tester.getSemantics(find.byKey(PauseCard.restartKey)).label,
        l10n.pairLabel(
          l10n.tripPauseRestart,
          l10n.tripPauseRestartCost(_numbers.integer(-1)),
        ),
      );
      semantics.dispose();
    });

    testWidgets('two AppSwitches save the preferences at once', (tester) async {
      final store = MemorySettingsStore();
      await pumpTrip(tester, settingsStore: store);
      await pressBack(tester);
      expect(_in(PauseCard, find.byType(AppSwitch)), findsNWidgets(2));
      expect(
        tester.widget<AppSwitch>(find.byKey(PauseCard.soundKey)).framed,
        isFalse,
      );

      await tester.tap(find.byKey(PauseCard.soundKey));
      await tester.pump();
      expect(store.values[tripSoundKey], 'off');
      await tester.tap(find.byKey(PauseCard.hapticsKey));
      await tester.pump();
      expect(store.values[tripHapticsKey], 'off');
      expect(
        tester.widget<AppSwitch>(find.byKey(PauseCard.soundKey)).value,
        isFalse,
      );
    });

    testWidgets('back resumes the trip', (tester) async {
      await pumpTrip(tester);
      await pressBack(tester);
      expect(find.byType(PauseCard), findsOneWidget);
      await pressBack(tester);
      expect(find.byType(PauseCard), findsNothing);
      expect(controllerOf(tester).phase, TripPhase.running);
    });
  });

  group('Fail', () {
    Future<void> pumpFailed(WidgetTester tester, {FailSummary? summary}) async {
      await pumpTrip(tester, tripId: cTripId);
      final model = failModel();
      await _show(
        tester,
        summary == null
            ? model
            : TripModel(
                phase: TripPhase.failed,
                view: cTripView(phase: TripPhase.failed, failSummary: summary),
                restartEnabled: true,
              ),
      );
    }

    testWidgets('up to three angry faces, the first in the middle', (
      tester,
    ) async {
      await pumpFailed(tester);
      final faces = find.descendant(
        of: find.byKey(FailureCard.facesKey),
        matching: find.byType(PassengerPortrait),
      );
      expect(faces, findsNWidgets(3));
      final shown = [
        for (final e in faces.evaluate())
          (e.widget as PassengerPortrait).passenger.passengerId,
      ];
      expect(shown.toSet(), failFaces.toSet());
      // The biggest is the first.
      final biggest = faces.evaluate().reduce(
        (a, b) =>
            tester.getSize(find.byWidget(a.widget)).height >=
                tester.getSize(find.byWidget(b.widget)).height
            ? a
            : b,
      );
      expect(
        (biggest.widget as PassengerPortrait).passenger.passengerId,
        failFaces.first,
      );
      expect(
        _in(FailureCard, find.text(_l10n(tester).tripFailTitle)),
        findsOneWidget,
      );
    });

    testWidgets('the reason chip: M02\'s two causes joined', (tester) async {
      await pumpFailed(tester);
      final l10n = _l10n(tester);
      final chip = find.byKey(FailureCard.reasonKey);
      expect(
        find.descendant(
          of: chip,
          matching: find.text(l10n.failCauses(failSummary(), _numbers)),
        ),
        findsOneWidget,
      );
      final pill = tester.widget<DecoratedBox>(
        find.descendant(of: chip, matching: find.byType(DecoratedBox)).first,
      );
      expect((pill.decoration as BoxDecoration).color, ColorTokens.dangerSoft);
    });

    testWidgets('a broken story rule leads the chip', (tester) async {
      const summary = FailSummary(
        causes: [FailCause(cause: RepCause.fight, count: 1)],
        revive: null,
        brokeStoryRule: true,
      );
      await pumpFailed(tester, summary: summary);
      final l10n = _l10n(tester);
      final lines = find.descendant(
        of: find.byKey(FailureCard.reasonKey),
        matching: find.byType(Text),
      );
      expect(
        [for (final e in lines.evaluate()) (e.widget as Text).data],
        [l10n.tripFailStoryRule, l10n.failCauses(summary, _numbers)],
      );
    });

    testWidgets('the revive and its line show only when offered', (
      tester,
    ) async {
      await pumpFailed(tester);
      final l10n = _l10n(tester);
      final revive = tester.widget<AppButton>(
        find.byKey(FailureCard.reviveKey),
      );
      expect(
        revive.label,
        l10n.tripFailRevive(_numbers.integer(failRevivePrice)),
      );
      expect(
        tester.widget<CardNote>(find.byKey(FailureCard.onceKey)).text,
        l10n.tripReviveOnce,
      );

      // Revived, then failed again: none is offered (nor at the cap).
      await _show(tester, cTripModel());
      await _show(tester, failModel(revive: null));
      expect(find.byKey(FailureCard.reviveKey), findsNothing);
      expect(find.byKey(FailureCard.onceKey), findsNothing);
      expect(find.byKey(FailureCard.adSlotKey), findsNothing);
      expect(find.text(l10n.tripReviveOnce), findsNothing);
    });

    testWidgets('both tiles, side by side', (tester) async {
      await pumpFailed(tester);
      final restart = tester.getRect(find.byKey(FailureCard.restartKey));
      final home = tester.getRect(find.byKey(FailureCard.homeKey));
      expect(restart.top, home.top);
      expect(restart.height, 48);
      expect(home.height, 48);
      expect(restart.left, greaterThan(home.right), reason: 'RTL');
      expect(
        find.descendant(
          of: find.byKey(FailureCard.restartKey),
          matching: find.byType(CostChip),
        ),
        findsOneWidget,
      );
    });

    testWidgets('back and the scrim leave it up', (tester) async {
      final f = loadFixture('ending__failed');
      await pumpTrip(
        tester,
        tripId: f.definition.tripId,
        fixed: FixedTrip(
          definition: f.definition,
          params: f.params,
          seed: f.seed,
        ),
      );
      final c = controllerOf(tester);
      while (c.phase == TripPhase.running) {
        c.advance(const Duration(milliseconds: engineStepMs));
      }
      await tester.pumpAndSettle();
      expect(find.byType(FailureCard), findsOneWidget);
      await pressBack(tester);
      expect(find.byType(FailureCard), findsOneWidget);
      await tester.tapAt(const Offset(195, 820));
      await tester.pumpAndSettle();
      expect(find.byType(FailureCard), findsOneWidget);
      expect(controllerOf(tester).phase, TripPhase.failed);
    });

    testWidgets('the empty ad slot keeps the revive at y 398', (tester) async {
      await pumpFailed(tester);
      expect(
        tester.getSize(find.byKey(FailureCard.adSlotKey)).height,
        DesignExtras.rewardedHeight,
      );
      expect(
        tester.getRect(find.byKey(FailureCard.reviveKey)).top,
        closeTo(398, 2),
      );
    });
  });

  group('the other cards', () {
    TripModel boosterModel({required int bonat, int? shortBy}) => TripModel(
      phase: TripPhase.boosterCard,
      view: cTripView(),
      boosterCard: BoosterCardModel(
        booster: BoosterId.trafficJam,
        priceBonat: 5,
        bonat: bonat,
        shortBy: shortBy,
      ),
    );

    testWidgets('the booster purchase: price, balance, buy beside close', (
      tester,
    ) async {
      await pumpTrip(tester, tripId: cTripId);
      await _show(tester, boosterModel(bonat: 3));
      final l10n = _l10n(tester);
      _expectDialog(tester, find.byKey(BoosterCard.buyKey));
      expect(find.text('بـ${_numbers.integer(5)} بون'), findsOneWidget);
      expect(find.text('معاك ${_numbers.integer(3)} بونات'), findsOneWidget);
      final buy = tester.getRect(find.byKey(BoosterCard.buyKey));
      final close = tester.getRect(find.byKey(BoosterCard.closeKey));
      expect(buy.top, close.top);
      expect(buy.width, greaterThan(close.width));
      expect(buy.left, greaterThan(close.right), reason: 'RTL: buy first');
      expect(
        tester.widget<CardTile>(find.byKey(BoosterCard.closeKey)).label,
        l10n.tripBoosterClose,
      );
    });

    testWidgets('short: the shortfall agrees with its number', (tester) async {
      await pumpTrip(tester, tripId: cTripId);
      await _show(tester, boosterModel(bonat: 3, shortBy: 12));
      expect(find.text('ناقصك ${_numbers.integer(12)} بون'), findsOneWidget);
      expect(find.byKey(BoosterCard.buyKey), findsNothing);
      expect(find.byKey(BoosterCard.closeKey), findsOneWidget);
    });

    testWidgets('the empty tank, a failed save and the dispute are dialogs', (
      tester,
    ) async {
      await pumpTrip(tester, tripId: cTripId);
      final l10n = _l10n(tester);

      await _show(
        tester,
        TripModel(phase: TripPhase.noFuel, view: cTripView()),
      );
      _expectDialog(tester, _in(NoFuelCard, find.text(l10n.tripNoFuelShop)));
      expect(_in(NoFuelCard, find.byType(CardActions)), findsOneWidget);

      await _show(
        tester,
        TripModel(
          phase: TripPhase.running,
          view: cTripView(),
          retry: TripRetry.start,
        ),
      );
      _expectDialog(tester, _in(RetryCard, find.text(l10n.tripRetryAction)));
      expect(_in(RetryCard, find.text(l10n.tripRetryHome)), findsOneWidget);

      await _show(
        tester,
        TripModel(
          phase: TripPhase.disputeOpen,
          view: cTripView(
            choices: const [
              DisputeChoice(disputeId: 1, a: 'p_A_l', b: 'p_A_r'),
            ],
          ),
        ),
      );
      _expectDialog(tester, find.byKey(DisputeCard.faceKey('p_A_l')));
      expect(
        _in(DisputeCard, find.text(l10n.tripDisputeTitle)),
        findsOneWidget,
      );
    });

    testWidgets('each sits on the scrim, in the spend-confirmation look', (
      tester,
    ) async {
      await pumpTrip(tester, tripId: cTripId);
      await _show(tester, boosterModel(bonat: 3));
      final card = tester.widget<TripCard>(find.byType(TripCard));
      expect(card.scrim, ColorTokens.scrim);
      expect(card.designTop, isNull);
    });
  });
}
