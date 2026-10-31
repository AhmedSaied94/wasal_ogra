import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show Size;
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/core/sync/server_status.dart';

import '../../helpers/lines.dart';
import '../../helpers/progress.dart';
import '../../helpers/surfaces.dart';
import '../../helpers/synthetic_packs.dart';
import '../design_check.dart';

// `AptGoal` and `AptGoalReady` as the boards draw them: chapter 3
// «تحويش الجواز», the shabka at the board's 6,000, 2,200 saved, and 6,240
// saved for the ready state. `artboardSalon()` carries the board's price.

Future<ProviderContainer> pumpAptGoal(
  WidgetTester tester, {
  bool ready = false,
  DigitStyle digits = DigitStyle.arabicIndic,
  Size? size,
  double textScale = 1.0,
  ServerStatusState serverStatus = const ServerStatusState(),
}) async {
  final (container, _) = await pumpLinesApp(
    tester,
    pack: artboardSalon(),
    digits: digits,
    textScale: textScale,
    serverStatus: serverStatus,
    location: '/apartment',
    state: playerState(
      jenehat: ready ? 6240 : 2200,
      stars: hayDone,
      owned: {microOld},
    ),
    // The goal bar animates and the clock idles: nothing settles.
    settle: false,
  );
  if (size == null) {
    applyDesignSurface(tester, const Size(390, 844), topInset: designTopInset);
  } else {
    applySurfaceSize(tester, size);
  }
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  return container;
}
