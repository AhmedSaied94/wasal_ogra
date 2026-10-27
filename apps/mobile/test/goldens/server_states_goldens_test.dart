import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/bootstrap/app.dart';
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/core/platform/store_launcher.dart';
import 'package:wassal/core/routing/router.dart';
import 'package:wassal/core/sync/server_status.dart';
import 'package:wassal/core/theme/components/buttons.dart';
import 'package:wassal/core/theme/components/overlays.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

import '../design/boxes.dart';
import '../helpers/pump_app.dart';
import '../helpers/server_status.dart';

// The server states over Home (specs/011-m06-identity-sync, contracts/
// server-states.md "Checks"), in RTL at 390×844 with both digit styles,
// and each placed component against its `States` box.

/// 16:30 on the device's clock, wherever the test runs.
final _untilMs = DateTime(2026, 10, 27, 16, 30).millisecondsSinceEpoch;

final _states = <String, ServerStatusState>{
  'offline': const ServerStatusState(reach: Reach.offline),
  'maintenance_at': ServerStatusState(
    maintenance: Maintenance(untilMs: _untilMs),
  ),
  'maintenance': const ServerStatusState(maintenance: Maintenance()),
  'update_forced': const ServerStatusState(update: ForcedUpdate()),
  'update_optional': const ServerStatusState(update: OptionalUpdate('1.2.0')),
};

Future<void> _pump(
  WidgetTester tester,
  ServerStatusState state,
  DigitStyle digits,
) async {
  await pumpWassalApp(
    tester,
    serverStatus: state,
    digits: digits,
    overrides: [storeLauncherProvider.overrideWithValue(FakeStoreLauncher())],
  );
  await tester.pumpAndSettle();
}

Future<void> _expectGolden(String name) => expectLater(
  find.byType(WassalApp),
  matchesGoldenFile('goldens/server_states_$name.png'),
);

/// [box]'s size and inline start within ±2 pt.
void _expectBox(Rect rect, DesignBox box) {
  expect(rect.left, closeTo(box.x, 2), reason: '$box left');
  expect(rect.width, closeTo(box.w, 2), reason: '$box width');
  expect(rect.height, closeTo(box.h, 2), reason: '$box height');
}

void main() {
  for (final digits in DigitStyle.values) {
    for (final MapEntry(key: name, value: state) in _states.entries) {
      testWidgets('${name}_${digits.name}', (tester) async {
        await _pump(tester, state, digits);
        await _expectGolden('${name}_${digits.name}');
      });
    }

    testWidgets('toast_${digits.name}', (tester) async {
      final container = await pumpWassalApp(tester, digits: digits);
      final navigator = container
          .read(routerProvider)
          .routerDelegate
          .navigatorKey
          .currentState!;
      showAppToastOn(
        navigator.overlay!,
        AppLocalizations.of(navigator.context).syncBalanceCorrected,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await _expectGolden('toast_${digits.name}');
      await tester.pump(MotionTokens.toastHold);
      await tester.pumpAndSettle();
    });
  }

  group('the States boxes, where they are placed', () {
    late DesignBoard board;
    setUpAll(() => board = loadBoard('States'));

    testWidgets('the offline banner (box 1)', (tester) async {
      await _pump(tester, _states['offline']!, DigitStyle.arabicIndic);
      _expectBox(tester.getRect(find.byType(OfflineBanner)), board.byId(1));
    });

    testWidgets('the update card (box 26) and its button (box 30)', (
      tester,
    ) async {
      await _pump(tester, _states['update_forced']!, DigitStyle.arabicIndic);
      final card = tester.getRect(find.byType(StatusCard));
      _expectBox(card, board.byId(26));

      final button = tester.getRect(
        find.descendant(
          of: find.byType(StatusCard),
          matching: find.byType(AppButton),
        ),
      );
      final box = board.byId(30);
      final drawnCard = board.byId(26);
      expect(button.width, closeTo(box.w, 2));
      expect(button.height, closeTo(box.h, 2));
      // Where it sits inside the card.
      expect(button.left - card.left, closeTo(box.x - drawnCard.x, 2));
      expect(button.top - card.top, closeTo(box.y - drawnCard.y, 2));
    });

    testWidgets('the maintenance card (box 31)', (tester) async {
      await _pump(tester, _states['maintenance_at']!, DigitStyle.arabicIndic);
      _expectBox(tester.getRect(find.byType(StatusCard)), board.byId(31));
    });
  });
}
