import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/routing/param_validators.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

/// Picks a string from the generated localizations, standing in for an ARB
/// key in the route table.
typedef L10nText = String Function(AppLocalizations l10n);

/// How a destination is shown (contracts/routes.md «Presentation types»).
enum Presentation { tab, page, sheet, overlay }

/// The bottom-bar branch a destination belongs to.
enum Section { home, lines, apartment, shop, none }

/// The tab sections in bar order, right to left.
const tabSections = [
  Section.home,
  Section.lines,
  Section.apartment,
  Section.shop,
];

/// Parameter values used by placeholder links (contracts/routes.md).
const sampleParams = {
  'tripId': 'line_hay.01',
  'lineId': 'line_hay',
  'vehicleId': 'micro_old',
  'itemId': 'salon.nish',
  'chapterId': 'ch1_first_job',
};

/// One MVP destination (data-model.md «Destination»). Later features keep
/// its name, path, presentation and links, and replace only its screen.
@immutable
class Destination {
  const Destination({
    required this.name,
    required this.path,
    required this.presentation,
    required this.title,
    this.section = Section.none,
    this.params = const {},
    this.links = const [],
  });

  final String name;

  /// The go_router path pattern; null for an overlay, which has no URL.
  final String? path;
  final Presentation presentation;
  final Section section;
  final Map<String, ParamValidator> params;

  /// Names of the destinations its placeholder links to (FR-017a).
  final List<String> links;
  final L10nText title;

  /// [path] filled in with [sampleParams].
  String get location =>
      path!.replaceAllMapped(RegExp(r':(\w+)'), (m) => sampleParams[m[1]]!);

  /// Whether every path parameter passes its rule.
  bool acceptsParams(Map<String, String> values) =>
      params.entries.every((rule) => rule.value(values[rule.key] ?? ''));
}

/// Destination names, for links and `goNamed`.
abstract final class RouteNames {
  static const boot = 'boot';
  static const onboardingIntro = 'onboardingIntro';
  static const onboardingName = 'onboardingName';
  static const home = 'home';
  static const preTrip = 'preTrip';
  static const trip = 'trip';
  static const tripPause = 'tripPause';
  static const result = 'result';
  static const lines = 'lines';
  static const lineDetail = 'lineDetail';
  static const vehiclePurchase = 'vehiclePurchase';
  static const apartment = 'apartment';
  static const apartmentItem = 'apartmentItem';
  static const apartmentRequests = 'apartmentRequests';
  static const apartmentChapters = 'apartmentChapters';
  static const story = 'story';
  static const shop = 'shop';
  static const fuel = 'fuel';
  static const dailyReward = 'dailyReward';
  static const dailyTasks = 'dailyTasks';
  static const dailyChallenge = 'dailyChallenge';
  static const settings = 'settings';
  static const account = 'account';
}

const _tripId = {'tripId': ParamValidators.tripId};

/// Every MVP destination from mobile §9. Garage, leagues, events and
/// referral are later phases and are not declared (FR-017).
final List<Destination> destinations = List.unmodifiable([
  Destination(
    name: RouteNames.boot,
    path: '/boot',
    presentation: Presentation.page,
    title: (l) => l.appName,
  ),
  Destination(
    name: RouteNames.onboardingIntro,
    path: '/onboarding/intro',
    presentation: Presentation.page,
    title: (l) => l.destOnboardingIntro,
    links: const [RouteNames.onboardingName],
  ),
  Destination(
    name: RouteNames.onboardingName,
    path: '/onboarding/name',
    presentation: Presentation.page,
    title: (l) => l.destOnboardingName,
    links: const [RouteNames.home],
  ),
  Destination(
    name: RouteNames.home,
    path: '/home',
    presentation: Presentation.tab,
    section: Section.home,
    title: (l) => l.destHome,
    links: const [
      RouteNames.preTrip,
      RouteNames.settings,
      RouteNames.dailyReward,
      RouteNames.dailyTasks,
      RouteNames.dailyChallenge,
    ],
  ),
  Destination(
    name: RouteNames.preTrip,
    path: '/home/pre-trip/:tripId',
    presentation: Presentation.sheet,
    section: Section.home,
    params: _tripId,
    title: (l) => l.destPreTrip,
    links: const [RouteNames.trip],
  ),
  Destination(
    name: RouteNames.trip,
    path: '/trip/:tripId',
    presentation: Presentation.page,
    params: _tripId,
    title: (l) => l.destTrip,
    links: const [RouteNames.result],
  ),
  Destination(
    name: RouteNames.tripPause,
    path: null,
    presentation: Presentation.overlay,
    title: (l) => l.pauseTitle,
    links: const [RouteNames.home],
  ),
  Destination(
    name: RouteNames.result,
    path: '/trip/:tripId/result',
    presentation: Presentation.page,
    params: _tripId,
    title: (l) => l.destResult,
    links: const [RouteNames.home, RouteNames.preTrip],
  ),
  Destination(
    name: RouteNames.lines,
    path: '/lines',
    presentation: Presentation.tab,
    section: Section.lines,
    title: (l) => l.destLines,
    links: const [RouteNames.lineDetail],
  ),
  Destination(
    name: RouteNames.lineDetail,
    path: '/lines/:lineId',
    presentation: Presentation.sheet,
    section: Section.lines,
    params: const {'lineId': ParamValidators.lineId},
    title: (l) => l.destLineDetail,
    links: const [RouteNames.vehiclePurchase],
  ),
  Destination(
    name: RouteNames.vehiclePurchase,
    path: '/lines/vehicle/:vehicleId',
    presentation: Presentation.sheet,
    section: Section.lines,
    params: const {'vehicleId': ParamValidators.vehicleId},
    title: (l) => l.destVehiclePurchase,
  ),
  Destination(
    name: RouteNames.apartment,
    path: '/apartment',
    presentation: Presentation.tab,
    section: Section.apartment,
    title: (l) => l.destApartment,
    links: const [
      RouteNames.apartmentItem,
      RouteNames.apartmentRequests,
      RouteNames.apartmentChapters,
    ],
  ),
  Destination(
    name: RouteNames.apartmentItem,
    path: '/apartment/item/:itemId',
    presentation: Presentation.sheet,
    section: Section.apartment,
    params: const {'itemId': ParamValidators.itemId},
    title: (l) => l.destApartmentItem,
  ),
  Destination(
    name: RouteNames.apartmentRequests,
    path: '/apartment/requests',
    presentation: Presentation.sheet,
    section: Section.apartment,
    title: (l) => l.destApartmentRequests,
  ),
  Destination(
    name: RouteNames.apartmentChapters,
    path: '/apartment/chapters',
    presentation: Presentation.page,
    title: (l) => l.destApartmentChapters,
    links: const [RouteNames.story],
  ),
  Destination(
    name: RouteNames.story,
    path: '/story/:chapterId',
    presentation: Presentation.page,
    params: const {'chapterId': ParamValidators.chapterId},
    title: (l) => l.destStory,
  ),
  Destination(
    name: RouteNames.shop,
    path: '/shop',
    presentation: Presentation.tab,
    section: Section.shop,
    title: (l) => l.destShop,
    links: const [RouteNames.fuel],
  ),
  Destination(
    name: RouteNames.fuel,
    path: '/shop/fuel',
    presentation: Presentation.sheet,
    section: Section.shop,
    title: (l) => l.destFuel,
  ),
  Destination(
    name: RouteNames.dailyReward,
    path: '/daily/reward',
    presentation: Presentation.page,
    title: (l) => l.destDailyReward,
  ),
  Destination(
    name: RouteNames.dailyTasks,
    path: '/daily/tasks',
    presentation: Presentation.page,
    title: (l) => l.destDailyTasks,
  ),
  Destination(
    name: RouteNames.dailyChallenge,
    path: '/daily/challenge',
    presentation: Presentation.page,
    title: (l) => l.destDailyChallenge,
  ),
  Destination(
    name: RouteNames.settings,
    path: '/settings',
    presentation: Presentation.page,
    title: (l) => l.destSettings,
    links: const [RouteNames.account],
  ),
  Destination(
    name: RouteNames.account,
    path: '/settings/account',
    presentation: Presentation.page,
    title: (l) => l.destAccount,
  ),
]);

final Map<String, Destination> _byName = {
  for (final d in destinations) d.name: d,
};

/// The destination called [name]; throws for an undeclared name.
Destination destinationNamed(String name) =>
    _byName[name] ?? (throw ArgumentError.value(name, 'name', 'undeclared'));
