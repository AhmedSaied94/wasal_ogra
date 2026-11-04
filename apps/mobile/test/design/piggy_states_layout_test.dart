import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/features/home/presentation/piggy_cards.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

import 'design_check.dart';
import 'samples/piggy_states.dart';

// M11's piggy boards against their measured boxes (specs/018-m11-ads,
// T064, contracts/design-briefs.md "As drawn"). `PiggyArrived` checks
// «تمام» (box 27) and the art (box 20); its wallet pills stay under the
// scrim, as every dialog's do, until M12 builds `PurchaseDone`'s sun ring
// (the boxes don't check the pills). `PiggyUsed` and `PiggyLater` are
// `C-Home` with the banner gone and the toast above the nav (box 70), so
// their Home boxes take `C-Home`'s pairings and differences. The boards
// leave the banner's slot empty; the app gives it to the street, so the
// cards under the scene sit its 52 and one 10 gap lower.

/// The banner's slot (`homePiggyHeight` and `homeGap`), which the street
/// takes once the banner hides.
const _bannerSlot = Offset(0, 62);

const _homePairings = {
  10: 'البنزين ٤ من ٥، اللتر الجاي بعد ١٣ دقيقة',
  63: 'الخطوط',
  65: 'الشقة، جديد',
  68: 'المحل',
};

void _expectRect(WidgetTester tester, Finder finder, Rect design) {
  final rect = tester.getRect(finder);
  for (final (edge, app, want) in [
    ('left', rect.left, design.left),
    ('top', rect.top, design.top),
    ('width', rect.width, design.width),
    ('height', rect.height, design.height),
  ]) {
    expect(app, closeTo(want, 2), reason: '$finder $edge');
  }
}

Future<void> _toast(
  WidgetTester tester,
  String board, {
  bool later = false,
}) async {
  final semantics = tester.ensureSemantics();
  await pumpPiggyToast(tester, later: later);
  expectLayoutMatches(
    tester,
    board,
    skip: const {16: 'the garage is phase 2 (FR-008)'},
    pairings: _homePairings,
    tolerances: const {8: 3.5},
    offsets: const {38: _bannerSlot, 47: _bannerSlot, 50: _bannerSlot},
    appOnly: const {'لوحة التجربة'},
  );
  _expectRect(
    tester,
    find.byType(PiggyToastIcon),
    const Rect.fromLTWH(330, 703, 30, 30),
  );
  final l10n = AppLocalizations.of(tester.element(find.byType(PiggyToastIcon)));
  final text = find.text(later ? l10n.piggyLater : l10n.piggyUsed);
  expect(tester.getRect(text).top, closeTo(708.9, 2));
  semantics.dispose();
}

void main() {
  testWidgets('PiggyArrived: the boxes', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpPiggyArrived(tester);
    expectLayoutMatches(
      tester,
      'PiggyArrived',
      appOnly: const {'لوحة التجربة'},
      scrim: 'قفل',
    );
    _expectRect(
      tester,
      find
          .descendant(
            of: find.byType(PiggyArrivedDialog),
            matching: find.byType(SvgPicture),
          )
          .first,
      const Rect.fromLTWH(95, 248, 200, 128),
    );
    final l10n = AppLocalizations.of(
      tester.element(find.byType(PiggyArrivedDialog)),
    );
    // The title (box 21) and the chips' box (box 22).
    expect(
      tester.getRect(find.text(l10n.piggyArrivedTitle)).top,
      closeTo(388, 2),
      reason: 'title ${tester.getRect(find.text(l10n.piggyArrivedTitle))}',
    );
    _expectRect(
      tester,
      find.byKey(PiggyArrivedDialog.chipsKey),
      const Rect.fromLTWH(34, 452, 322, 76),
    );
    expect(find.byKey(PiggyArrivedDialog.okKey), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('PiggyUsed: the boxes', (tester) => _toast(tester, 'PiggyUsed'));

  testWidgets(
    'PiggyLater: the boxes',
    (tester) => _toast(tester, 'PiggyLater', later: true),
  );
}
