import 'dart:collection';

import 'package:content_models/content_models.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/routing/placeholder_screen.dart';
import 'package:wassal/core/routing/routes.dart';
import 'package:wassal/core/theme/components/nav.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/home/application/home_slots.dart';
import 'package:wassal/features/home/presentation/home_header.dart';
import 'package:wassal/features/home/presentation/start_button.dart';
import 'package:wassal/features/lines/presentation/line_card.dart';
import 'package:wassal/features/lines/presentation/line_details_sheet.dart';
import 'package:wassal/features/lines/presentation/vehicle_strip.dart';
import 'package:wassal/features/pre_trip/presentation/pre_trip_card.dart';

/// Presses the phone's back button.
Future<void> pressBack(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

/// The real screens' controls for the links their placeholders had (M08):
/// the profile opens Settings, «يلا نطلع!» the next trip's card, and the
/// card's «اطلع» the trip. Lines' (M09): خط الحي's card opens its details,
/// the old microbus's tile its sheet, and the details' button the card.
final _homeControls = <String, Key>{
  RouteNames.settings: HomeHeader.profileKey,
  RouteNames.preTrip: HomeStartButton.startKey,
  RouteNames.trip: PreTripCard.goKey,
  RouteNames.lineDetail: LineCard.keyOf(LineId.lineHay),
  RouteNames.vehiclePurchase: VehicleTileView.keyOf(VehicleId.microOld),
  RouteNames.linePreTrip: LineDetailsSheet.playKey,
};

/// Home's daily row (M13's slot) as placeholder links, so the daily
/// destinations stay reachable in tests until M13 builds it.
Override homeDailyLinks() => homeDailyRowProvider.overrideWithValue(
  (context) => SizedBox(
    width: _dailyLinksWidth,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      spacing: SpaceTokens.s4,
      children: [
        for (final name in [
          RouteNames.dailyReward,
          RouteNames.dailyTasks,
          RouteNames.dailyChallenge,
        ])
          PlaceholderLink(
            from: destinationNamed(RouteNames.home),
            to: destinationNamed(name),
          ),
      ],
    ),
  ),
);

const double _dailyLinksWidth = 180;

/// Taps the visible link to [name]: a placeholder's, or Home's own control
/// for it, scrolling it into view when content above it pushed it down.
Future<void> tapLink(WidgetTester tester, String name) async {
  var key = find.byKey(PlaceholderScreen.linkKey(name));
  if (key.evaluate().isEmpty && _homeControls[name] != null) {
    key = find.byKey(_homeControls[name]!);
  }
  if (key.hitTestable().evaluate().isEmpty && key.evaluate().isNotEmpty) {
    await tester.ensureVisible(key.last);
    await tester.pumpAndSettle();
  }
  final link = key.hitTestable();
  expect(link, findsOneWidget, reason: 'link to $name');
  await tester.tap(link);
  await tester.pumpAndSettle();
}

/// The shortest chain of placeholder links from [start] to [target],
/// excluding [start] itself, or null when [target] is unreachable.
List<String>? linkPath(String start, String target) {
  final byName = {for (final d in destinations) d.name: d};
  final previous = <String, String>{};
  final queue = Queue.of([start]);
  final seen = {start};
  while (queue.isNotEmpty) {
    final name = queue.removeFirst();
    if (name == target) {
      final path = <String>[];
      for (String? n = target; n != null && n != start; n = previous[n]) {
        path.insert(0, n);
      }
      return path;
    }
    for (final next in byName[name]!.links) {
      if (seen.add(next)) {
        previous[next] = name;
        queue.add(next);
      }
    }
  }
  return null;
}

/// The tab destination that hosts [section].
Destination tabFor(Section section) => destinations.firstWhere(
  (d) => d.presentation == Presentation.tab && d.section == section,
);

/// Taps the bottom-bar cell for [section].
Future<void> tapTab(WidgetTester tester, Section section) async {
  await tester.tap(find.byKey(BottomNav.cellKey(tabSections.indexOf(section))));
  await tester.pumpAndSettle();
}

/// How the player reaches [target] from a fresh start on الموقف: the tab to
/// open from the bottom bar, then the chain of placeholder links.
({Section tab, List<String> links})? routeTo(String target) {
  for (final section in tabSections) {
    final links = linkPath(tabFor(section).name, target);
    if (links != null) return (tab: section, links: links);
  }
  return null;
}
