import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/core/theme/components/overlays.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/home/application/home_slots.dart';
import 'package:wassal/features/home/application/piggy_banner_state.dart';
import 'package:wassal/features/home/presentation/home_screen.dart';
import 'package:wassal/features/home/presentation/piggy_banner.dart';
import 'package:wassal/features/home/presentation/piggy_cards.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

import 'c_home.dart';

// M11's piggy boards (specs/018-m11-ads, T064): `C-Home` after the
// banner's ad, its banner gone, with `PiggyArrived`'s dialog (+30 ج and
// +2 بون) or the `PiggyUsed` / `PiggyLater` toast above the nav.

/// `PiggyArrived`'s grant.
const piggyArrivedJenehat = 30;
const piggyArrivedBonat = 2;

/// Hidden by the ad it just showed: the banner's space stays.
Future<ProviderContainer> _home(WidgetTester tester, DigitStyle digits) =>
    pumpCHome(
      tester,
      digits: digits,
      piggy: null,
      overrides: [
        morningPiggySlotProvider.overrideWithValue((_) => const PiggyBanner()),
        piggyBannerProvider.overrideWithValue(PiggyBannerState.hidden),
      ],
    );

/// `PiggyArrived`: the dialog over Home.
Future<ProviderContainer> pumpPiggyArrived(
  WidgetTester tester, {
  DigitStyle digits = DigitStyle.arabicIndic,
}) async {
  final container = await _home(tester, digits);
  final navigator = Navigator.of(
    tester.element(find.byType(HomeScreen)),
    rootNavigator: true,
  );
  final _ = navigator.push(
    appDialogRoute<void>(
      context: navigator.context,
      builder: (_) => const PiggyArrivedDialog(
        jenehat: piggyArrivedJenehat,
        bonat: piggyArrivedBonat,
      ),
    ),
  );
  for (var i = 0; i < 16; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  return container;
}

/// `PiggyUsed`, or `PiggyLater` when [later]: the toast over Home.
Future<ProviderContainer> pumpPiggyToast(
  WidgetTester tester, {
  bool later = false,
  DigitStyle digits = DigitStyle.arabicIndic,
}) async {
  final container = await _home(tester, digits);
  final context = tester.element(find.byType(HomeScreen));
  final l10n = AppLocalizations.of(context);
  showAppToast(
    context,
    later ? l10n.piggyLater : l10n.piggyUsed,
    leading: PiggyToastIcon(later: later),
  );
  await tester.pump();
  await tester.pump(MotionTokens.toast);
  return container;
}
