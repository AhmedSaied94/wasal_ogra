import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/ads/ads_gateway.dart';
import 'package:wassal/core/ads/ads_providers.dart';
import 'package:wassal/core/ads/ads_service.dart';
import 'package:wassal/core/ads/piggy_api.dart';
import 'package:wassal/core/ads/piggy_service.dart';
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/core/l10n/number_formatter.dart';
import 'package:wassal/core/network/api_client.dart';
import 'package:wassal/core/sync/domain/wire/bootstrap.dart';
import 'package:wassal/features/home/application/home_slots.dart';
import 'package:wassal/features/home/application/piggy_banner_state.dart';
import 'package:wassal/features/home/presentation/piggy_banner.dart';
import 'package:wassal/features/home/presentation/piggy_cards.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

import '../../design/samples/c_home.dart';
import '../../helpers/ads.dart';
import '../../helpers/fake_ads_gateway.dart';
import '../../helpers/piggy.dart';

// Home's morning piggy (specs/018-m11-ads, contracts/seams.md
// "`PiggyBanner`", T046): each state's look, and the card each outcome
// opens.

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(PiggyBanner)));

Finder _inChip(Finder finder) =>
    find.descendant(of: find.byKey(PiggyBanner.chipKey), matching: finder);

void main() {
  group('states', () {
    test('from the offer and the asking', () {
      expect(
        piggyBannerStateOf(const Offered(), asking: false),
        PiggyBannerState.ready,
      );
      expect(
        piggyBannerStateOf(const NotReady(), asking: false),
        PiggyBannerState.notReady,
      );
      expect(
        piggyBannerStateOf(const NeedsNetwork(), asking: false),
        PiggyBannerState.offline,
      );
      expect(
        piggyBannerStateOf(const Hidden(), asking: false),
        PiggyBannerState.hidden,
      );
      expect(
        piggyBannerStateOf(const Hidden(), asking: true),
        PiggyBannerState.asking,
      );
    });

    testWidgets('ready: «ببلاش», tappable', (tester) async {
      await pumpCHome(tester);
      expect(_inChip(find.text(_l10n(tester).piggyCta)), findsOneWidget);
      expect(find.bySemanticsLabel('حصّالة الصبح، ببلاش'), findsOneWidget);
    });

    testWidgets('not ready', (tester) async {
      await pumpCHome(tester, piggy: PiggyBannerState.notReady);
      expect(_inChip(find.text(_l10n(tester).adNotReady)), findsOneWidget);
    });

    testWidgets('offline: «محتاج نت»', (tester) async {
      await pumpCHome(tester, piggy: PiggyBannerState.offline);
      expect(_inChip(find.text(_l10n(tester).adNeedsNetwork)), findsOneWidget);
    });

    testWidgets('asking: the wheel, no text', (tester) async {
      await pumpCHome(tester, piggy: PiggyBannerState.asking);
      expect(find.text(_l10n(tester).piggyCta), findsNothing);
      expect(find.bySemanticsLabel(_l10n(tester).piggyAsking), findsOneWidget);
    });

    testWidgets('hidden: no space', (tester) async {
      await pumpCHome(tester, piggy: PiggyBannerState.hidden);
      expect(find.byType(PiggyBanner), findsNothing);
    });
  });

  group('outcomes', () {
    Future<void> tapWith(WidgetTester tester, List<ApiResult> answers) async {
      final rig = await tester.runAsync(
        () =>
            AdsRig.open(gateway: FakeAdsGateway(ready: {AdUnit.morningPiggy})),
      );
      rig!.world.adsBlock = const AdsBlock(piggyAvailable: true, unseen: []);
      await tester.runAsync(rig.service.ensureReady);
      final piggy = PiggyService(
        ads: rig.service,
        api: PiggyApi(ScriptedPiggyServer(answers)),
        economy: rig.economy.service,
        playerId: () => 'p-1',
        requestSync: (_) {},
        wait: (_) async {},
      );
      await pumpCHome(
        tester,
        piggy: null,
        overrides: [
          morningPiggySlotProvider.overrideWithValue(
            (_) => const PiggyBanner(),
          ),
          piggyBannerProvider.overrideWithValue(PiggyBannerState.ready),
          piggyServiceProvider.overrideWithValue(piggy),
        ],
      );
      await tester.tap(find.byKey(PiggyBanner.bannerKey));
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('granted opens the reward dialog', (tester) async {
      await tapWith(tester, [piggyGranted()]);
      expect(find.byType(PiggyArrivedDialog), findsOneWidget);
      final l10n = AppLocalizations.of(
        tester.element(find.byType(PiggyArrivedDialog)),
      );
      const numbers = NumberFormatter(DigitStyle.arabicIndic);
      expect(
        find.text(l10n.piggyJenehatChip(numbers.integer(30))),
        findsOneWidget,
      );
      expect(
        find.text(l10n.piggyBonatChip(numbers.integer(2))),
        findsOneWidget,
      );
      await tester.tap(find.byKey(PiggyArrivedDialog.okKey));
      await tester.pumpAndSettle();
      expect(find.byType(PiggyArrivedDialog), findsNothing);
    });

    testWidgets('refused says today\'s piggy is used', (tester) async {
      await tapWith(tester, [piggyRefused('cap_reached')]);
      expect(find.text(_l10n(tester).piggyUsed), findsOneWidget);
    });

    testWidgets('no answer says it comes later', (tester) async {
      await tapWith(tester, []);
      expect(find.text(_l10n(tester).piggyLater), findsOneWidget);
    });
  });
}
