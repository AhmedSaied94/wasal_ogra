import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/bootstrap/app.dart';
import 'package:wassal/bootstrap/flavor.dart';
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/l10n/number_formatter.dart';
import 'package:wassal/core/routing/router.dart';
import 'package:wassal/core/sync/server_status.dart';
import 'package:wassal/core/theme/app_theme.dart';
import 'package:wassal/core/theme/components/overlays.dart';
import 'package:wassal/features/home/home_status_area.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

import '../../helpers/pump_app.dart';
import '../../helpers/server_status.dart';
import '../../helpers/surfaces.dart';

// Home's server states (specs/011-m06-identity-sync, contracts/
// server-states.md "Placements").

const _offline = ServerStatusState(reach: Reach.offline);

/// 16:30 on the device's clock, wherever the test runs.
final _untilMs = DateTime(2026, 10, 27, 16, 30).millisecondsSinceEpoch;

final _childKey = UniqueKey();

/// Counts its taps: Home's own state.
class _Counter extends StatefulWidget {
  const _Counter({super.key});

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int taps = 0;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => setState(() => taps++),
    child: SizedBox.expand(child: Text('$taps')),
  );
}

Future<PinnedServerStatus> _pump(
  WidgetTester tester,
  ServerStatusState state, {
  DigitStyle digits = DigitStyle.arabicIndic,
}) async {
  applySurface(tester, Surface.reference);
  final status = PinnedServerStatus(state);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        serverStatusProvider.overrideWith(() => status),
        numberFormatterProvider.overrideWithValue(NumberFormatter(digits)),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        locale: appLocale,
        supportedLocales: const [appLocale],
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        home: HomeStatusArea(child: _Counter(key: _childKey)),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return status;
}

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(HomeStatusArea)));

void main() {
  testWidgets('online with no maintenance: nothing, and no height', (
    tester,
  ) async {
    await _pump(tester, const ServerStatusState());

    expect(find.byType(OfflineBanner), findsNothing);
    expect(find.byType(StatusCard), findsNothing);
    expect(tester.getTopLeft(find.byKey(_childKey)).dy, 0);
  });

  testWidgets('offline: the banner, above Home', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, _offline);

    expect(find.text(_l10n(tester).homeOffline), findsOneWidget);
    final banner = tester.getRect(find.byType(OfflineBanner));
    expect(tester.getTopLeft(find.byKey(_childKey)).dy, banner.bottom);
    expect(
      tester.getSemantics(find.byType(OfflineBanner)),
      isSemantics(isLiveRegion: true),
    );
    semantics.dispose();
  });

  for (final digits in DigitStyle.values) {
    testWidgets('maintenance with an end: the local time in ${digits.name}', (
      tester,
    ) async {
      await _pump(
        tester,
        ServerStatusState(maintenance: Maintenance(untilMs: _untilMs)),
        digits: digits,
      );

      final l10n = _l10n(tester);
      final time = NumberFormatter(digits).clockTime(16, 30);
      expect(
        time,
        contains(digits == DigitStyle.arabicIndic ? '٤:٣٠' : '4:30'),
      );
      expect(find.text(l10n.maintenanceTitle), findsOneWidget);
      expect(find.text(l10n.maintenanceMessageAt(time)), findsOneWidget);
    });
  }

  testWidgets('maintenance without an end', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, const ServerStatusState(maintenance: Maintenance()));

    expect(find.text(_l10n(tester).maintenanceMessage), findsOneWidget);
    expect(
      tester.getSemantics(
        find
            .ancestor(
              of: find.byType(StatusCard),
              matching: find.byType(Semantics),
            )
            .first,
      ),
      isSemantics(isLiveRegion: true),
    );
    semantics.dispose();
  });

  testWidgets('offline wins over maintenance', (tester) async {
    await _pump(
      tester,
      const ServerStatusState(reach: Reach.offline, maintenance: Maintenance()),
    );

    expect(find.byType(OfflineBanner), findsOneWidget);
    expect(find.byType(StatusCard), findsNothing);
  });

  testWidgets('Home keeps its state when a card comes and goes', (
    tester,
  ) async {
    final status = await _pump(tester, const ServerStatusState());
    await tester.tap(find.byKey(_childKey));
    await tester.pump();

    status.pin(_offline);
    await tester.pumpAndSettle();
    expect(find.byType(OfflineBanner), findsOneWidget);
    expect(find.text('1'), findsOneWidget);

    status.pin(const ServerStatusState());
    await tester.pumpAndSettle();
    expect(find.byType(OfflineBanner), findsNothing);
    expect(find.text('1'), findsOneWidget);
  });

  for (final flavor in Flavor.values) {
    testWidgets('it wraps Home in ${flavor.name}, and only Home', (
      tester,
    ) async {
      final container = await pumpWassalApp(
        tester,
        flavor: flavor,
        serverStatus: _offline,
      );
      expect(find.byType(HomeStatusArea), findsOneWidget);
      expect(find.byType(OfflineBanner), findsOneWidget);

      container.read(routerProvider).go('/settings');
      await tester.pumpAndSettle();
      expect(find.byType(OfflineBanner).hitTestable(), findsNothing);
    });
  }

  testWidgets('the real status: an unreachable server shows the banner', (
    tester,
  ) async {
    await pumpWassalApp(tester, serverStatus: null);

    expect(find.byType(OfflineBanner), findsOneWidget);
  });
}
