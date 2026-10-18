import 'dart:async';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/bootstrap/startup.dart';
import 'package:wassal/core/routing/routes.dart';

import 'routing.dart';

/// A screen state the a11y and golden suites render, by name: open
/// [location] with [overrides], then run [then] if set.
class ScreenCase {
  const ScreenCase(
    this.name, {
    this.location,
    this.overrides = const [],
    this.then,
  });

  final String name;
  final String? location;
  final List<Override> overrides;
  final Future<void> Function(WidgetTester tester)? then;
}

/// Boot stays on screen while startup never finishes.
List<Override> pendingStartup() => [
  appStartupProvider.overrideWith((ref) => Completer<void>().future),
];

List<Override> failedStartup() => [
  appStartupProvider.overrideWith(
    (ref) => Future<void>.error(StateError('startup failed')),
  ),
];

/// The US1 screens: boot (loading and failed) and the four tabs.
List<ScreenCase> shellScreens() => [
  ScreenCase('boot', overrides: pendingStartup()),
  ScreenCase('boot_error', overrides: failedStartup()),
  const ScreenCase('home', location: '/home'),
  const ScreenCase('lines', location: '/lines'),
  const ScreenCase('apartment', location: '/apartment'),
  const ScreenCase('shop', location: '/shop'),
];

/// The US2 screens: every page and sheet, and the trip pause.
List<ScreenCase> navigationScreens() => [
  for (final d in destinations)
    if (d.presentation == Presentation.page && d.name != RouteNames.boot ||
        d.presentation == Presentation.sheet)
      ScreenCase(d.name, location: d.location),
  ScreenCase(
    RouteNames.tripPause,
    location: destinationNamed(RouteNames.trip).location,
    then: pressBack,
  ),
];

const textScales = [1.0, 1.3];
