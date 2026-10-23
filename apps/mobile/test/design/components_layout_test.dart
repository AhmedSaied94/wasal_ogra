import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

import '../helpers/design_component.dart';
import 'boxes.dart';
import 'design_check.dart';
import 'samples/components.dart';

// The `Components` board's eight tap boxes against the sample's tappables
// (contracts/design-checks.md), with no skips.

void main() {
  testWidgets('Components: every tap box', (tester) async {
    final semantics = tester.ensureSemantics();
    final board = loadBoard('Components');
    await pumpDesignComponent(
      tester,
      ComponentsSample(board: board, digits: DigitStyle.arabicIndic),
      size: ComponentsSample.size,
      background: ColorTokens.paper,
    );
    await tester.pump(const Duration(milliseconds: 300));
    final l10n = AppLocalizations.of(
      tester.element(find.byType(ComponentsSample)),
    );
    final (title, benefit) = ComponentsSample.rewarded(DigitStyle.arabicIndic);
    expectLayoutMatches(
      tester,
      'Components',
      board: board,
      pairings: {
        // Boxes 3 and 6 share their text; 6 is the pressed look.
        3: 'يلا نطلع!',
        6: ComponentsSample.pressedLabel,
        // The rewarded button has no text of its own: its two lines.
        10: l10n.pairLabel(title, benefit),
      },
      appOnly: {
        // The board draws these as samples, not as tap boxes.
        'إيقاف مؤقت',
        'قفل',
        'الصوت',
        'الصالة',
        'المطبخ',
        'الترقيات',
        'الزينة',
        'الاسم',
        l10n.undoCountdown('٣'),
        'الموقف',
        'الخطوط',
        l10n.pairLabel('الشقة', 'جديد'),
        'المحل',
      },
    );
    semantics.dispose();
  });
}
