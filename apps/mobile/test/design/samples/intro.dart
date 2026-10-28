import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/l10n/digit_style.dart';

import '../../helpers/pump_app.dart';
import '../design_check.dart';

// `Intro` as a new player first sees it (specs/012-m07-onboarding/contracts/
// ci-checks.md): boot hands over to the sample's `opening` scene, panel 1,
// on the design's surface with its 36 pt status bar.

Future<void> pumpIntro(
  WidgetTester tester, {
  DigitStyle digits = DigitStyle.arabicIndic,
}) async {
  await pumpWassalApp(tester, newPlayer: true, digits: digits);
  applyDesignSurface(tester, const Size(390, 844), topInset: designTopInset);
  await tester.pumpAndSettle();
}
