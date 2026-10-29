import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/bootstrap/app.dart' show appLocale;
import 'package:wassal/core/routing/routes.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

import '../design/samples/lines.dart';
import '../helpers/screens.dart';
import 'minimum_sizes_test.dart' show expectMinimumSizes;

// `Lines`'s minimum sizes (specs/014-m09-lines-vehicles, T031, T047, T058,
// T106; constitution XI): targets ≥ 44×44 and text ≥ 12 at text scale 1.0
// and 1.3, on the small, the tall-narrow and the reference phone, with
// nothing cut short — the artboard's state, a line done at three stars,
// offline, and 1.3× on a 360 phone.

const _phones = [Size(360, 640), Size(360, 800), Size(390, 844)];

void main() {
  late Set<String> titles;

  setUpAll(() async {
    final l10n = await AppLocalizations.delegate.load(appLocale);
    titles = {for (final d in destinations) d.title(l10n)};
  });

  final states = <(String, Future<void> Function(WidgetTester, Size, double))>[
    (
      'artboard',
      (tester, size, scale) => pumpLines(tester, size: size, textScale: scale),
    ),
    (
      'done at three',
      (tester, size, scale) =>
          pumpLinesDoneAtThree(tester, size: size, textScale: scale),
    ),
    (
      'offline',
      (tester, size, scale) =>
          pumpLinesOffline(tester, size: size, textScale: scale),
    ),
  ];

  for (final (name, pump) in states) {
    for (final size in _phones) {
      for (final scale in textScales) {
        testWidgets(
          'Lines $name · ${size.width.round()}×${size.height.round()} · '
          '×$scale',
          (tester) => expectMinimumSizes(
            tester,
            titles,
            (tester) => pump(tester, size, scale),
          ),
        );
      }
    }
  }
}
