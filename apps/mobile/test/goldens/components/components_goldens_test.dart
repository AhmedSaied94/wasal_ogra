import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/core/l10n/number_formatter.dart';
import 'package:wassal/features/dev/gallery/components_page.dart';

import '../../helpers/design_component.dart';

// The gallery's components page, one golden per section, at 390 wide, RTL,
// in both digit styles (contracts/components.md "Tests").

void main() {
  for (final section in gallerySections) {
    for (final digits in DigitStyle.values) {
      testWidgets('${section.name}, ${digits.name}', (tester) async {
        await pumpDesignComponent(
          tester,
          SizedBox(
            width: 390,
            child: GallerySectionView(
              section: section,
              numbers: NumberFormatter(digits),
            ),
          ),
          size: const Size(390, 1700),
          center: false,
        );
        // Entrances (the banner's slide) finish; loops stop where they are.
        await tester.pump(const Duration(milliseconds: 300));
        await expectLater(
          find.byType(GallerySectionView),
          matchesGoldenFile('goldens/${section.name}_${digits.name}.png'),
        );
      });
    }
  }
}
