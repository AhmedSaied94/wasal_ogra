import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/routing/placeholder_screen.dart';
import 'package:wassal/core/routing/routes.dart';
import 'package:wassal/core/theme/components/wassal_bottom_bar.dart';

/// Presses the phone's back button.
Future<void> pressBack(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

/// Taps the visible placeholder link to [name], scrolling it into view
/// when content above it (internal builds' trip list) pushed it down.
Future<void> tapLink(WidgetTester tester, String name) async {
  final key = find.byKey(PlaceholderScreen.linkKey(name));
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
  await tester.tap(
    find.byKey(WassalBottomBar.cellKey(tabSections.indexOf(section))),
  );
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
