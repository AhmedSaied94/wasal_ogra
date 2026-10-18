import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/bootstrap/app.dart';
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/core/routing/new_dot_providers.dart';
import 'package:wassal/core/routing/routes.dart';

import '../helpers/pump_app.dart';
import '../helpers/routing.dart';
import '../helpers/screens.dart';
import '../helpers/surfaces.dart';

// US2 and US3 goldens (FR-040): a page, a sheet, the trip pause, settings,
// and each tab with the «new» dot on, at both surfaces, both text scales
// and both digit styles. Tabs with the dot off are the US1 shell goldens.

Future<void> expectGolden(String name) =>
    expectLater(find.byType(WassalApp), matchesGoldenFile('goldens/$name.png'));

void main() {
  for (final surface in Surface.values) {
    for (final scale in textScales) {
      for (final digits in DigitStyle.values) {
        final suffix = '${surface.name}_${scale}_${digits.name}';

        Future<dynamic> open(WidgetTester tester, String location) =>
            pumpWassalApp(
              tester,
              initialLocation: location,
              surface: surface,
              textScale: scale,
              digits: digits,
            );

        testWidgets('page_story_$suffix', (tester) async {
          await open(tester, '/story/ch1_first_job');
          await expectGolden('page_story_$suffix');
        });

        testWidgets('sheet_pre_trip_$suffix', (tester) async {
          await open(tester, '/home/pre-trip/line_hay.01');
          await expectGolden('sheet_pre_trip_$suffix');
        });

        testWidgets('trip_pause_$suffix', (tester) async {
          await open(tester, '/trip/line_hay.01');
          await pressBack(tester);
          await expectGolden('trip_pause_$suffix');
        });

        testWidgets('settings_$suffix', (tester) async {
          await open(tester, '/settings');
          await expectGolden('settings_$suffix');
        });

        for (final section in tabSections) {
          testWidgets('dot_${section.name}_$suffix', (tester) async {
            // Stand on another tab: the open tab never keeps its dot.
            final container = await pumpWassalApp(
              tester,
              initialLocation: section == Section.home ? '/lines' : '/home',
              surface: surface,
              textScale: scale,
              digits: digits,
            );
            container.read(newDotProvider(section).notifier).show();
            await tester.pumpAndSettle();
            await expectGolden('dot_${section.name}_$suffix');
          });
        }
      }
    }
  }
}
