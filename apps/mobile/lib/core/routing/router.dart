import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:trip_engine/trip_engine.dart' show TripOutcome;
import 'package:wassal/bootstrap/startup.dart';
import 'package:wassal/core/economy/economy_providers.dart';
import 'package:wassal/core/platform/launch_metrics.dart';
import 'package:wassal/core/routing/app_page.dart';
import 'package:wassal/core/routing/param_validators.dart';
import 'package:wassal/core/routing/placeholder_screen.dart';
import 'package:wassal/core/routing/routes.dart';
import 'package:wassal/core/routing/shell_scaffold.dart';
import 'package:wassal/core/theme/components/overlays.dart';
import 'package:wassal/features/boot/boot_screen.dart';
import 'package:wassal/features/onboarding/domain/first_session.dart';
import 'package:wassal/features/onboarding/onboarding_providers.dart';
import 'package:wassal/features/onboarding/presentation/fuel_lesson_screen.dart';
import 'package:wassal/features/onboarding/presentation/name_screen.dart';
import 'package:wassal/features/onboarding/presentation/scene_page.dart';
import 'package:wassal/core/economy/domain/wire.dart';
import 'package:wassal/core/glossary/ids.dart' as glossary;
import 'package:wassal/features/home/presentation/home_screen.dart';
import 'package:wassal/features/lines/presentation/line_details_sheet.dart';
import 'package:wassal/features/lines/presentation/lines_screen.dart';
import 'package:wassal/features/lines/presentation/vehicle_sheet.dart';
import 'package:wassal/features/trip/domain/line_ids.dart';
import 'package:wassal/features/pre_trip/presentation/pre_trip_card.dart';
import 'package:wassal/features/result/domain/result_args.dart';
import 'package:wassal/features/result/presentation/result_screen.dart';
import 'package:wassal/features/settings/settings_screen.dart';
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
          : (_, state) {
              final params = state.pathParameters;
              if (!d.acceptsParams(params)) return '/home';
              // A card opened from Lines sits under its own line's details:
              // a trip of another line goes to the details it named.
              if (d.name == RouteNames.linePreTrip &&
                  !params['tripId']!.startsWith('${params['lineId']}.')) {
                return '/lines/${params['lineId']}';
              }
              return null;
            },
      pageBuilder: (context, state) => _page(context, state, d),
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
      return _resultRedirect(ref, state) ?? _firstSessionRedirect(ref, state);
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
          // `vehicle/:vehicleId` before `:lineId`, which would match it. The
          // card opened from Lines sits under the line's details, so its
          // close lands there (specs/014-m09-lines-vehicles, research R5).
          StatefulShellBranch(
            routes: [
              route(
                RouteNames.lines,
                routes: [
                  route(RouteNames.vehiclePurchase, under: '/lines'),
                  route(
                    RouteNames.lineDetail,
                    under: '/lines',
                    routes: [
                      route(RouteNames.linePreTrip, under: '/lines/:lineId'),
                    ],
                  ),
                ],
              ),
            ],
          ),
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
/// once startup has completed. A scene due at Home is no longer one: Home's
/// arrival queue plays it (specs/013-m08-home-result, research R9).
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

/// A result with nothing to show, neither the trip's hand-over nor a
/// finished last result, is الموقف before any page is built
/// (specs/013-m08-home-result FR-036).
String? _resultRedirect(Ref ref, GoRouterState state) {
  if (!_result.hasMatch(state.matchedLocation)) return null;
  if (state.extra is ResultArgs) return null;
  final last = ref.read(economyViewProvider).lastResult;
  return last != null && last.outcome == TripOutcome.finished ? null : '/home';
}

final _result = RegExp(r'^/trip/[^/]+/result$');

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

Page<void> _page(BuildContext context, GoRouterState state, Destination d) {
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
    RouteNames.home => const HomeScreen(),
    RouteNames.lines => const LinesScreen(),
    RouteNames.lineDetail => LineDetailsSheet(
      lineId: toContentLine(
        glossary.LineId.fromWire(state.pathParameters['lineId']!)!,
      ),
    ),
    RouteNames.vehiclePurchase => VehicleSheet(
      vehicle: fromWire(vehicleWire, state.pathParameters['vehicleId'])!,
    ),
    // The card opened from Lines: an unopenable trip leaves to the line.
    RouteNames.linePreTrip => PreTripCard(
      key: ValueKey(state.pathParameters['tripId']),
      tripId: state.pathParameters['tripId']!,
      leaveTo: '/lines/${state.pathParameters['lineId']}',
    ),
    // Keyed, as the trip is: another trip's card is another card.
    RouteNames.preTrip => PreTripCard(
      key: ValueKey(state.pathParameters['tripId']),
      tripId: state.pathParameters['tripId']!,
    ),
    // The trip hands over its ResultArgs; a bare TripResult (M07's path
    // until it updates) or nothing shows the last result's pay.
    RouteNames.result => ResultScreen(
      tripId: state.pathParameters['tripId']!,
      args: switch (state.extra) {
        final ResultArgs args => args,
        _ => null,
      },
    ),
    _ => PlaceholderScreen(destination: d, params: state.pathParameters),
  };
  return switch (d.presentation) {
    Presentation.tab => NoTransitionPage(
      key: state.pageKey,
      name: d.name,
      // Cold start ends when الموقف first draws (FR-012a).
      // Home puts M06's status area under its header itself
      // (specs/013-m08-home-result, `HomeStates`).
      child: d.name == RouteNames.home
          ? ReportFullyDrawn(child: screen)
          : screen,
    ),
    Presentation.sheet => AppSheetPage(
      key: state.pageKey,
      name: d.name,
      title: d.title(AppLocalizations.of(context)),
      // The card's two-line heading is its own (`PreTrip` boxes 9–11), and
      // so are the details' and the vehicle sheet's (`LineDetails`,
      // `BuyVehicle` block 2b).
      ownHeader: const {
        RouteNames.preTrip,
        RouteNames.linePreTrip,
        RouteNames.lineDetail,
        RouteNames.vehiclePurchase,
      }.contains(d.name),
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
