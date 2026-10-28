import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/routing/router.dart';
import 'package:wassal/core/routing/routes.dart';

import '../../helpers/pump_app.dart';

// The destination table (contracts/routes.md, FR-014, FR-017), with M07's
// two first-session routes (specs/012-m07-onboarding/contracts/
// first-session.md "New routes").

const _p = Presentation.page;
const _s = Presentation.sheet;
const _t = Presentation.tab;
const _none = Section.none;

const expected = <String, (String?, Presentation, Section, List<String>)>{
  'boot': ('/boot', _p, _none, []),
  'onboardingIntro': ('/onboarding/intro', _p, _none, ['onboardingName']),
  'onboardingName': ('/onboarding/name', _p, _none, ['trip', 'home']),
  'onboardingScene': (
    '/onboarding/scene/:sceneId',
    _p,
    _none,
    ['trip', 'home'],
  ),
  'onboardingFuel': ('/onboarding/fuel', _p, _none, ['trip']),
  'home': (
    '/home',
    _t,
    Section.home,
    ['preTrip', 'settings', 'dailyReward', 'dailyTasks', 'dailyChallenge'],
  ),
  'preTrip': ('/home/pre-trip/:tripId', _s, Section.home, ['trip']),
  'trip': ('/trip/:tripId', _p, _none, ['result']),
  'tripPause': (null, Presentation.overlay, _none, ['home']),
  'result': ('/trip/:tripId/result', _p, _none, ['home', 'preTrip']),
  'lines': ('/lines', _t, Section.lines, ['lineDetail']),
  'lineDetail': ('/lines/:lineId', _s, Section.lines, ['vehiclePurchase']),
  'vehiclePurchase': ('/lines/vehicle/:vehicleId', _s, Section.lines, []),
  'apartment': (
    '/apartment',
    _t,
    Section.apartment,
    ['apartmentItem', 'apartmentRequests', 'apartmentChapters'],
  ),
  'apartmentItem': ('/apartment/item/:itemId', _s, Section.apartment, []),
  'apartmentRequests': ('/apartment/requests', _s, Section.apartment, []),
  'apartmentChapters': ('/apartment/chapters', _p, _none, ['story']),
  'story': ('/story/:chapterId', _p, _none, []),
  'shop': ('/shop', _t, Section.shop, ['fuel']),
  'fuel': ('/shop/fuel', _s, Section.shop, []),
  'dailyReward': ('/daily/reward', _p, _none, []),
  'dailyTasks': ('/daily/tasks', _p, _none, []),
  'dailyChallenge': ('/daily/challenge', _p, _none, []),
  'settings': ('/settings', _p, _none, ['account']),
  'account': ('/settings/account', _p, _none, []),
};

void main() {
  test('the table matches contracts/routes.md exactly', () {
    expect(destinations.map((d) => d.name).toList(), expected.keys.toList());
    for (final d in destinations) {
      final (path, presentation, section, links) = expected[d.name]!;
      expect(d.path, path, reason: d.name);
      expect(d.presentation, presentation, reason: d.name);
      expect(d.section, section, reason: d.name);
      expect(d.links, links, reason: d.name);
    }
  });

  test('the four tabs are home, lines, apartment, shop, in order', () {
    expect(
      destinations
          .where((d) => d.presentation == Presentation.tab)
          .map((d) => d.name),
      ['home', 'lines', 'apartment', 'shop'],
    );
    expect(tabSections, [
      Section.home,
      Section.lines,
      Section.apartment,
      Section.shop,
    ]);
  });

  test('links point at declared destinations', () {
    final names = destinations.map((d) => d.name).toSet();
    for (final d in destinations) {
      expect(names, containsAll(d.links), reason: d.name);
    }
  });

  test('each path parameter has a validator and a sample', () {
    for (final d in destinations.where((d) => d.path != null)) {
      final names = RegExp(r':(\w+)')
          .allMatches(d.path!)
          .map((m) => m[1]!)
          .toSet();
      expect(d.params.keys.toSet(), names, reason: d.name);
      for (final name in names) {
        expect(sampleParams[name], isNotNull, reason: name);
        expect(d.params[name]!(sampleParams[name]!), isTrue, reason: name);
      }
      expect(d.location, isNot(contains(':')), reason: d.name);
    }
  });

  test('later-phase destinations are not declared (FR-017)', () {
    for (final d in destinations) {
      for (final banned in ['garage', 'leagues', 'events', 'referral']) {
        expect(d.path ?? '', isNot(contains(banned)), reason: d.name);
        expect(d.name.toLowerCase(), isNot(contains(banned)), reason: d.name);
      }
    }
  });

  testWidgets('the router registers every destination by name and path', (
    tester,
  ) async {
    final container = await pumpWassalApp(tester);
    final router = container.read(routerProvider);
    for (final d in destinations.where((d) => d.path != null)) {
      final params = {for (final k in d.params.keys) k: sampleParams[k]!};
      expect(
        router.namedLocation(d.name, pathParameters: params),
        d.location,
        reason: d.name,
      );
    }
  });

  group('safeThen: only a trip or الموقف (first-session.md "Router")', () {
    test('a trip by a valid id, and /home, pass', () {
      expect(safeThen('/trip/line_hay.01'), '/trip/line_hay.01');
      expect(safeThen('/home'), '/home');
    });

    for (final bad in [
      null,
      '',
      'https://evil.example/trip/line_hay.01',
      '//evil.example',
      '/trip/line_xyz.01',
      '/trip/line_hay.01/result',
      '/trip/line_hay.01?x=1',
      '/settings/account',
      '/onboarding/fuel',
      'trip/line_hay.01',
      '/home/pre-trip/line_hay.01',
    ]) {
      test('${bad ?? 'null'} becomes /home', () {
        expect(safeThen(bad), '/home');
      });
    }
  });
}
