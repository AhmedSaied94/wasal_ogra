import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/platform/store_launcher.dart';
import 'package:wassal/core/routing/router.dart';
import 'package:wassal/core/sync/server_status.dart';
import 'package:wassal/core/theme/components/buttons.dart';
import 'package:wassal/core/theme/components/overlays.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

import '../helpers/memory_settings_store.dart';
import '../helpers/pump_app.dart';
import '../helpers/server_status.dart';

// The update card over the app (specs/011-m06-identity-sync, contracts/
// server-states.md "Placements", research R18).

const _forced = ServerStatusState(update: ForcedUpdate());
const _optional = ServerStatusState(update: OptionalUpdate('1.2.0'));

final class _App {
  _App(this.container, this.store, this.settings);

  final ProviderContainer container;
  final FakeStoreLauncher store;
  final MemorySettingsStore settings;

  PinnedServerStatus get status =>
      container.read(serverStatusProvider.notifier) as PinnedServerStatus;

  void go(String location) => container.read(routerProvider).go(location);

  String get path => container.read(routerProvider).state.uri.path;
}

Future<_App> _pump(
  WidgetTester tester, {
  ServerStatusState status = const ServerStatusState(),
  bool hasListing = true,
  String? initialLocation,
}) async {
  final store = FakeStoreLauncher(hasListing: hasListing);
  final settings = MemorySettingsStore({
    DigitStyleNotifier.key: DigitStyle.arabicIndic.wire,
  });
  final container = await pumpWassalApp(
    tester,
    serverStatus: status,
    settingsStore: settings,
    initialLocation: initialLocation,
    overrides: [storeLauncherProvider.overrideWithValue(store)],
  );
  await tester.pumpAndSettle();
  return _App(container, store, settings);
}

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(StatusCard)));

Finder get _card => find.byType(StatusCard);

void main() {
  group('forced', () {
    testWidgets('a dialog over Home with its title, message and button', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _pump(tester, status: _forced);

      expect(_card, findsOneWidget);
      expect(find.byType(AppDialog), findsOneWidget);
      final l10n = _l10n(tester);
      expect(find.text(l10n.updateTitle), findsOneWidget);
      expect(find.text(l10n.updateMessage), findsOneWidget);
      expect(find.text(l10n.updateCta), findsOneWidget);
      expect(find.text(l10n.updateLater), findsNothing);
      expect(
        tester.getSemantics(
          find
              .descendant(
                of: find.byType(AppDialog),
                matching: find.byType(Semantics),
              )
              .first,
        ),
        isSemantics(
          label: l10n.updateTitle,
          scopesRoute: true,
          namesRoute: true,
        ),
      );
      semantics.dispose();
    });

    testWidgets('back does nothing', (tester) async {
      final app = await _pump(tester, status: _forced);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(_card, findsOneWidget);
      expect(app.path, '/home');
    });

    testWidgets('a tap outside does nothing, and reaches nothing beneath', (
      tester,
    ) async {
      final app = await _pump(tester, status: _forced);

      // The bottom bar's far cell.
      await tester.tapAt(const Offset(30, 820));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(195, 60));
      await tester.pumpAndSettle();

      expect(_card, findsOneWidget);
      expect(app.path, '/home');
    });

    testWidgets('the button opens the store, and is 44 pt or taller', (
      tester,
    ) async {
      final app = await _pump(tester, status: _forced);
      final button = find.widgetWithText(AppButton, _l10n(tester).updateCta);

      expect(tester.getSize(button).height, greaterThanOrEqualTo(44));
      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(app.store.opened, 1);
      expect(_card, findsOneWidget, reason: 'it stays until a new launch');
    });

    testWidgets('no listing, no button; it still blocks', (tester) async {
      final app = await _pump(tester, status: _forced, hasListing: false);

      expect(_card, findsOneWidget);
      expect(
        find.descendant(of: _card, matching: find.byType(AppButton)),
        findsNothing,
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(_card, findsOneWidget);
      expect(app.path, '/home');
    });

    testWidgets('a navigation that takes the page beneath shows it again', (
      tester,
    ) async {
      final app = await _pump(tester, initialLocation: '/settings/account');
      app.status.pin(_forced);
      await tester.pumpAndSettle();
      expect(_card, findsOneWidget);

      app.go('/home');
      await tester.pumpAndSettle();

      expect(app.path, '/home');
      expect(_card, findsOneWidget);
    });
  });

  group('optional', () {
    testWidgets('«بعدين» closes it and keeps the version', (tester) async {
      final app = await _pump(tester, status: _optional);
      final l10n = _l10n(tester);
      expect(find.text(l10n.updateCta), findsOneWidget);

      await tester.tap(find.text(l10n.updateLater));
      await tester.pumpAndSettle();

      expect(_card, findsNothing);
      expect(app.settings.values[dismissedUpdateKey], '1.2.0');
      expect(app.status.state.update, const NoUpdate());
    });

    testWidgets('back does nothing either', (tester) async {
      await _pump(tester, status: _optional);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(_card, findsOneWidget);
    });

    testWidgets('it turns forced in place', (tester) async {
      final app = await _pump(tester, status: _optional);

      app.status.pin(_forced);
      await tester.pumpAndSettle();

      expect(_card, findsOneWidget);
      expect(find.text(_l10n(tester).updateLater), findsNothing);
    });
  });

  testWidgets('it waits while the trip shows, and shows on leaving it', (
    tester,
  ) async {
    final app = await _pump(tester, initialLocation: '/trip/line_hay.01');

    app.status.pin(_forced);
    await tester.pumpAndSettle();
    expect(_card, findsNothing);

    app.go('/home');
    await tester.pumpAndSettle();
    expect(_card, findsOneWidget);
  });

  for (final reduced in [false, true]) {
    testWidgets(
      reduced
          ? 'reduced motion: a fade without movement'
          : 'it scales in as the dialogs do',
      (tester) async {
        if (reduced) {
          tester.platformDispatcher.accessibilityFeaturesTestValue =
              const FakeAccessibilityFeatures(disableAnimations: true);
          addTearDown(
            tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
          );
        }
        final app = await _pump(tester);

        app.status.pin(_forced);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 40));

        final above = find.ancestor(
          of: find.byType(AppDialog),
          matching: find.byType(ScaleTransition),
        );
        expect(above, reduced ? findsNothing : findsWidgets);
        expect(
          find.ancestor(
            of: find.byType(AppDialog),
            matching: find.byType(FadeTransition),
          ),
          findsWidgets,
        );
        await tester.pumpAndSettle();
      },
    );
  }
}
