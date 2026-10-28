import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:trip_engine/trip_engine.dart' show TripResult;
import 'package:wassal/bootstrap/flavor.dart';
import 'package:wassal/bootstrap/startup.dart';
import 'package:wassal/core/economy/economy_providers.dart';
import 'package:wassal/core/platform/launch_metrics.dart';
import 'package:wassal/core/routing/app_page.dart';
import 'package:wassal/core/routing/param_validators.dart';
import 'package:wassal/core/routing/placeholder_screen.dart';
import 'package:wassal/core/routing/routes.dart';
import 'package:wassal/core/routing/shell_scaffold.dart';
import 'package:wassal/core/theme/components/overlays.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/boot/boot_screen.dart';
import 'package:wassal/features/onboarding/domain/first_session.dart';
import 'package:wassal/features/onboarding/onboarding_providers.dart';
import 'package:wassal/features/onboarding/presentation/driver_name_line.dart';
import 'package:wassal/features/onboarding/presentation/first_session_continue.dart';
import 'package:wassal/features/onboarding/presentation/fuel_lesson_screen.dart';
import 'package:wassal/features/onboarding/presentation/name_reask_host.dart';
import 'package:wassal/features/onboarding/presentation/name_screen.dart';
import 'package:wassal/features/onboarding/presentation/scene_page.dart';
import 'package:wassal/features/dev/gallery/gallery_entry.dart';
import 'package:wassal/features/dev/onboarding_card.dart';
import 'package:wassal/features/dev/sync_status_card.dart';
import 'package:wassal/features/home/home_status_area.dart';
import 'package:wassal/features/settings/settings_screen.dart';
import 'package:wassal/features/trip/presentation/playtest/result_summary.dart';
import 'package:wassal/features/trip/presentation/playtest/trip_list.dart';
import 'package:wassal/features/trip/presentation/trip_screen.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

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
    // boot may show until startup completes. Boot then goes to الموقف, or
    // into the first session (specs/012-m07-onboarding).
    redirect: (_, state) {
      if (!ref.read(appStartupProvider).hasValue) {
        return state.matchedLocation == '/boot' ? null : '/boot';
      }
      return _firstSessionRedirect(ref, state);
    },
    routes: [
      GoRoute(
        name: RouteNames.boot,
        path: '/boot',
        builder: (_, _) => const BootScreen(),
      ),
      route(RouteNames.onboardingIntro),
      route(RouteNames.onboardingName),
      route(RouteNames.onboardingScene),
      route(RouteNames.onboardingFuel),
      StatefulShellRoute(
        builder: (_, _, navigationShell) =>
            ShellScaffold(navigationShell: navigationShell),
        navigatorContainerBuilder: (_, navigationShell, children) =>
            TabCrossFade(
              currentIndex: navigationShell.currentIndex,
              children: children,
            ),
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

/// The first session's redirects (specs/012-m07-onboarding/contracts/
/// first-session.md "Router"), read from providers that are synchronous
/// once startup has completed.
String? _firstSessionRedirect(Ref ref, GoRouterState state) {
  final location = state.matchedLocation;
  if (location == '/onboarding/intro' &&
      ref.read(tutorialPlanProvider).openingScene == null) {
    // The playtest card's `then` goes along.
    return Uri(
      path: '/onboarding/name',
      queryParameters: state.uri.queryParameters.isEmpty
          ? null
          : state.uri.queryParameters,
    ).toString();
  }
  if (location == '/home') {
    return switch (ref.read(firstSessionProvider).onArrivalAtHome()) {
      DueScene(:final sceneId) => _sceneThen(sceneId, '/home'),
      null => null,
    };
  }
  // A trip's start, never the unfinished trip's resume.
  final tripId = _tripStart.firstMatch(location)?[1];
  if (tripId == null ||
      tripId == ref.read(economyViewProvider).unfinished?.tripId) {
    return null;
  }
  return switch (ref.read(firstSessionProvider).beforeStart(tripId)) {
    DueScene(:final sceneId) => _sceneThen(sceneId, '/trip/$tripId'),
    FuelLessonDue() => Uri(
      path: '/onboarding/fuel',
      queryParameters: {'then': tripId},
    ).toString(),
    null => null,
  };
}

final _tripStart = RegExp(r'^/trip/([^/]+)$');

String _sceneThen(String sceneId, String then) => Uri(
  path: '/onboarding/scene/$sceneId',
  queryParameters: {'then': then},
).toString();

/// Where a `then` query parameter may send the player: a trip by a valid id,
/// or الموقف. Anything else, from a link or a stale record, becomes الموقف.
String safeThen(String? then) {
  if (then == null) return '/home';
  final trip = RegExp(r'^/trip/([^/?#]+)$').firstMatch(then);
  if (trip != null && ParamValidators.tripId(trip[1]!)) return then;
  return '/home';
}

Page<void> _page(
  BuildContext context,
  GoRouterState state,
  Destination d, {
  required bool playtest,
}) {
  final screen = switch (d.name) {
    RouteNames.onboardingIntro => ScenePage.opening(
      then: state.uri.queryParameters['then'],
    ),
    RouteNames.onboardingName => NameScreen(
      then: state.uri.queryParameters['then'],
    ),
    RouteNames.onboardingFuel => FuelLessonScreen(
      then: state.uri.queryParameters['then'],
    ),
    RouteNames.onboardingScene => ScenePage(
      sceneId: state.pathParameters['sceneId']!,
      then: state.uri.queryParameters['then'],
    ),
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
      extra: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: SpaceTokens.s16,
        children: [DriverNameLine(), TripList(), GalleryEntry()],
      ),
      // Below Home's links, so they stay where they were.
      footer: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: SpaceTokens.s16,
        children: [OnboardingCard(), SyncStatusCard()],
      ),
    ),
    // M08 replaces it.
    RouteNames.result => PlaceholderScreen(
      destination: d,
      params: state.pathParameters,
      extra: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: SpaceTokens.s16,
        children: [
          ResultSummary(
            result: switch (state.extra) {
              final TripResult result => result,
              _ => null,
            },
          ),
          FirstSessionContinue(tripId: state.pathParameters['tripId']!),
        ],
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
          ? ReportFullyDrawn(
              child: HomeStatusArea(child: NameReaskHost(child: screen)),
            )
          : screen,
    ),
    Presentation.sheet => AppSheetPage(
      key: state.pageKey,
      name: d.name,
      title: d.title(AppLocalizations.of(context)),
      child: screen,
    ),
    Presentation.page || Presentation.overlay => AppPage(
      key: state.pageKey,
      name: d.name,
      reduceMotion: MediaQuery.disableAnimationsOf(context),
      child: screen,
    ),
  };
}
