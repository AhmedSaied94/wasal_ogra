import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/economy/domain/economy_state.dart';
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/core/l10n/number_formatter.dart';
import 'package:wassal/core/theme/components/controls.dart';
import 'package:wassal/features/trip/application/trip_phase.dart';
import 'package:wassal/features/trip/application/trip_settings.dart';
import 'package:wassal/features/trip/presentation/cards/pause_card.dart';
import 'package:wassal/features/trip/presentation/top_bar/top_bar.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

import '../../../helpers/economy.dart';
import '../../../helpers/memory_settings_store.dart';
import '../../../helpers/routing.dart';
import '../../../helpers/trip.dart';

// The pause card (tasks.md T049, FR-013, ux-spec «نافذة الإيقاف»).

/// 008.5: the switch is the whole `AppSwitch` row.
Finder _switchIn(Key toggle) => find.byKey(toggle);

void main() {
  testWidgets('the pause button and back both show it', (tester) async {
    await pumpTrip(tester);
    await tester.tap(find.byKey(TripHud.pauseKey));
    await tester.pumpAndSettle();
    expect(find.byType(PauseCard), findsOneWidget);
    expect(controllerOf(tester).model.pauseReason, PauseReason.button);

    await tester.tap(find.text('كمّل المشوار'));
    await tester.pumpAndSettle();
    expect(find.byType(PauseCard), findsNothing);
    expect(controllerOf(tester).phase, TripPhase.running);

    await pressBack(tester);
    expect(find.byType(PauseCard), findsOneWidget);
    expect(controllerOf(tester).model.pauseReason, PauseReason.back);
  });

  testWidgets('it has the three actions, the liter and two switches', (
    tester,
  ) async {
    await pumpTrip(tester);
    await pressBack(tester);
    final card = find.byType(PauseCard);
    for (final label in ['كمّل المشوار', 'عيد المشوار', 'ارجع الموقف']) {
      expect(
        find.descendant(of: card, matching: find.text(label)),
        findsOneWidget,
      );
    }
    // 008.5: the liter is the fuel chip «−١» (HANDOFF §9.1 #4).
    final liter = const NumberFormatter(DigitStyle.arabicIndic).integer(1);
    expect(
      find.text(lookupAppLocalizations(const Locale('ar')).tripFuelChip(liter)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.byType(AppSwitch)),
      findsNWidgets(2),
    );
    expect(find.text('الصوت'), findsOneWidget);
    expect(find.text('الاهتزاز'), findsOneWidget);
  });

  testWidgets('the switches save at once', (tester) async {
    final store = MemorySettingsStore();
    await pumpTrip(tester, settingsStore: store);
    await pressBack(tester);

    await tester.tap(_switchIn(PauseCard.soundKey));
    await tester.pump();
    expect(store.values[tripSoundKey], 'off');
    expect(store.values[tripHapticsKey], 'on');

    await tester.tap(_switchIn(PauseCard.hapticsKey));
    await tester.pump();
    expect(store.values[tripHapticsKey], 'off');

    await tester.tap(_switchIn(PauseCard.soundKey));
    await tester.pump();
    expect(store.values[tripSoundKey], 'on');
  });

  testWidgets('restart is unavailable with an empty tank', (tester) async {
    final economy = await testEconomy(
      firstState: (nowMs) => EconomyState.newPlayer(
        fuelMax: 5,
        nowMs: nowMs,
      ).copyWith(fuel: FuelState(liters: 1, countedFromMs: nowMs)),
    );
    await pumpTrip(tester, economy: economy);
    expect(economy.service.view.fuel.liters, 0);
    await pressBack(tester);

    expect(find.text('البنزين خلص'), findsOneWidget);
    final semantics = tester.ensureSemantics();
    expect(
      tester.getSemantics(find.byKey(PauseCard.restartKey)),
      isNot(matchesSemantics(isEnabled: true, hasEnabledState: true)),
    );
    semantics.dispose();
    await tester.tap(find.byKey(PauseCard.restartKey));
    await tester.pumpAndSettle();
    expect(controllerOf(tester).phase, TripPhase.paused);
    expect(economy.service.view.unfinished, isNotNull);
  });

  testWidgets('coming back to the app shows the card', (tester) async {
    await pumpTrip(tester);
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();
    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pumpAndSettle();
    expect(controllerOf(tester).phase, TripPhase.paused);
    expect(controllerOf(tester).model.pauseReason, PauseReason.lifecycle);
    expect(find.byType(PauseCard), findsOneWidget);
  });
}
