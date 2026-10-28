import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/features/onboarding/onboarding_providers.dart';
import 'package:wassal/features/onboarding/presentation/scene_player.dart';

import '../../helpers/pump_app.dart';
import '../design_check.dart';

// `Name` as a new player reaches it: «تخطّى» on the opening, then the card
// with the board's sample name, «حمادة», in the field.

/// The seed whose first suggestion is the pool's first name, «حمادة».
const nameSampleSeed = 24;

Future<void> pumpName(
  WidgetTester tester, {
  DigitStyle digits = DigitStyle.arabicIndic,
}) async {
  await pumpWassalApp(
    tester,
    newPlayer: true,
    digits: digits,
    overrides: [nameSeedProvider.overrideWithValue(nameSampleSeed)],
  );
  applyDesignSurface(tester, const Size(390, 844), topInset: designTopInset);
  await tester.tap(find.byKey(ScenePlayer.skipKey));
  await tester.pumpAndSettle();
}
