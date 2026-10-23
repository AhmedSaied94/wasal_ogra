import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:trip_engine/trip_engine.dart' show TripResult;
import 'package:wassal/bootstrap/flavor.dart';
import 'package:wassal/bootstrap/startup.dart';
import 'package:wassal/core/platform/launch_metrics.dart';
import 'package:wassal/core/routing/placeholder_screen.dart';
import 'package:wassal/core/routing/routes.dart';
import 'package:wassal/core/routing/sheet_page.dart';
import 'package:wassal/core/routing/shell_scaffold.dart';
import 'package:wassal/core/routing/sticker_page.dart';
import 'package:wassal/features/boot/boot_screen.dart';
import 'package:wassal/features/settings/settings_screen.dart';
import 'package:wassal/features/trip/presentation/playtest/result_summary.dart';
import 'package:wassal/features/trip/presentation/playtest/trip_list.dart';
import 'package:wassal/features/trip/presentation/trip_screen.dart';

part 'router.g.dart';

/// The app router, built from the destination table (contracts/routes.md).
///
/// - Tabs live in a `StatefulShellRoute`, one branch each, so each keeps
///   its state (FR-016).
/// - Pages and sheets sit on the root navigator, above the bar (FR-015).
///   A tab's sheets and pages nest under the tab, so the tab shows beneath
///   them and back returns to it.
/// - Invalid parameters redirect to الموقف; unknown paths reach
///   `onException`, the only error hook (go_router asserts on more), which
///   also goes to الموقف (FR-022).
@Riverpod(keepAlive: true)
GoRouter router(Ref ref) {
  final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');
  // The playtest tools are on dev and staging only (research R21).
  final playtest = ref.read(flavorProvider) != Flavor.prod;

  GoRoute route(
    String name, {
    String? under,
    List<RouteBase> routes = const [],
  }) {
    final d = destinationNamed(name);
    final path = d.path!;
    return GoRoute(
      name: d.name,
      path: under == null ? path : path.substring(under.length + 1),
      parentNavigatorKey: d.presentation == Presentation.tab
          ? null
          : rootNavigatorKey,
      redirect: d.params.isEmpty
          ? null
          : (_, state) =>
                d.acceptsParams(state.pathParameters) ? null : '/home',
      pageBuilder: (context, state) =>
          _page(context, state, d, playtest: playtest),
      routes: routes,
    );
  }

  StatefulShellBranch branch(String tab, List<String> children) {
    final path = destinationNamed(tab).path!;
    return StatefulShellBranch(
      routes: [
        route(
          tab,
          routes: [for (final child in children) route(child, under: path)],
        ),
      ],
    );
  }

  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/boot',
    onException: (_, _, router) => router.go('/home'),
    // Screens read the settings store and tunables synchronously, so only
    // boot may show until startup completes. Boot then goes to الموقف.
    redirect: (_, state) =>
        ref.read(appStartupProvider).hasValue ||
            state.matchedLocation == '/boot'
        ? null
        : '/boot',
    routes: [
      GoRoute(
        name: RouteNames.boot,
        path: '/boot',
        builder: (_, _) => const BootScreen(),
      ),
      route(RouteNames.onboardingIntro),
      route(RouteNames.onboardingName),
      StatefulShellRoute.indexedStack(
        builder: (_, _, navigationShell) =>
            ShellScaffold(navigationShell: navigationShell),
        branches: [
          branch(RouteNames.home, [RouteNames.preTrip]),
          // `vehicle/:vehicleId` before `:lineId`, which would match it.
          branch(RouteNames.lines, [
            RouteNames.vehiclePurchase,
            RouteNames.lineDetail,
          ]),
          branch(RouteNames.apartment, [
            RouteNames.apartmentItem,
            RouteNames.apartmentRequests,
            RouteNames.apartmentChapters,
          ]),
          branch(RouteNames.shop, [RouteNames.fuel]),
        ],
      ),
      route(RouteNames.trip),
      route(RouteNames.result),
      route(RouteNames.story),
      route(RouteNames.dailyReward),
      route(RouteNames.dailyTasks),
      route(RouteNames.dailyChallenge),
      route(
        RouteNames.settings,
        routes: [route(RouteNames.account, under: '/settings')],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
}

Page<void> _page(
  BuildContext context,
  GoRouterState state,
  Destination d, {
  required bool playtest,
}) {
  final screen = switch (d.name) {
    RouteNames.settings => const SettingsScreen(),
    // Keyed: another trip in the same page is another screen, with its own
    // controller.
    RouteNames.trip => TripScreen(
      key: ValueKey(state.pathParameters['tripId']),
      tripId: state.pathParameters['tripId']!,
    ),
    RouteNames.home when playtest => PlaceholderScreen(
      destination: d,
      params: state.pathParameters,
      extra: const TripList(),
    ),
    // M08 replaces it.
    RouteNames.result => PlaceholderScreen(
      destination: d,
      params: state.pathParameters,
      extra: ResultSummary(
        result: switch (state.extra) {
          final TripResult result => result,
          _ => null,
        },
      ),
    ),
    _ => PlaceholderScreen(destination: d, params: state.pathParameters),
  };
  return switch (d.presentation) {
    Presentation.tab => NoTransitionPage(
      key: state.pageKey,
      name: d.name,
      // Cold start ends when الموقف first draws (FR-012a).
      child: d.name == RouteNames.home
          ? ReportFullyDrawn(child: screen)
          : screen,
    ),
    Presentation.sheet => SheetPage(
      key: state.pageKey,
      name: d.name,
      child: screen,
    ),
    Presentation.page || Presentation.overlay => StickerPage(
      key: state.pageKey,
      name: d.name,
      reduceMotion: MediaQuery.disableAnimationsOf(context),
      child: screen,
    ),
  };
}
