import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/bootstrap/ads_overrides.dart';
import 'package:wassal/core/ads/ads_gateway.dart';
import 'package:wassal/core/ads/ads_providers.dart';
import 'package:wassal/core/ads/ads_service.dart';
import 'package:wassal/core/ads/piggy_api.dart';
import 'package:wassal/core/ads/piggy_service.dart';
import 'package:wassal/core/sync/domain/wire/bootstrap.dart';
import 'package:wassal/features/home/application/home_slots.dart';
import 'package:wassal/features/home/application/piggy_banner_state.dart';

import '../../helpers/ads.dart';
import '../../helpers/fake_ads_gateway.dart';
import '../../helpers/piggy.dart';

// The app's scope wires the ads' warm-up (specs/018-m11-ads, review H1);
// without it the refill offer could stay «not ready» with nothing loading it.
// It wires Settings' privacy row too (T081); without that, a European player
// could never get back to the consent form.

final class _RequiresPrivacy implements AdsService {
  @override
  Future<bool> privacyOptionsRequired() async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

void main() {
  test('the default does nothing; the app takes the live one', () {
    final tests = ProviderContainer();
    addTearDown(tests.dispose);
    expect(tests.read(adWarmUpProvider), same(noAdWarmUp));

    final app = ProviderContainer(overrides: adsOverrides());
    addTearDown(app.dispose);
    expect(app.read(adWarmUpProvider), isNot(same(noAdWarmUp)));
  });

  test('the privacy row: no by default; the app asks the service', () async {
    final tests = ProviderContainer();
    addTearDown(tests.dispose);
    expect(await tests.read(adPrivacyRequiredProvider.future), isFalse);

    final app = ProviderContainer(
      overrides: [
        ...adsOverrides(),
        adsServiceProvider.overrideWithValue(_RequiresPrivacy()),
      ],
    );
    addTearDown(app.dispose);
    expect(await app.read(adPrivacyRequiredProvider.future), isTrue);
  });

  // The boards keep Home's cards in place under the piggy's toast (owner's
  // decision, 2026-11-05), and a Home with no piggy gives the street the room.
  group('the piggy slot', () {
    Future<PiggyService> piggy() async {
      final rig = await AdsRig.open(
        gateway: FakeAdsGateway(ready: {AdUnit.morningPiggy}),
      );
      rig.world.adsBlock = const AdsBlock(piggyAvailable: true, unseen: []);
      await rig.service.ensureReady();
      final service = PiggyService(
        ads: rig.service,
        api: PiggyApi(ScriptedPiggyServer(const [])),
        economy: rig.economy.service,
        playerId: () => 'p-1',
        requestSync: (_) {},
        wait: (_) async {},
      );
      addTearDown(service.dispose);
      return service;
    }

    ProviderContainer app(PiggyService service, PiggyBannerState state) {
      final container = ProviderContainer(
        overrides: [
          ...adsOverrides(),
          piggyServiceProvider.overrideWithValue(service),
          piggyBannerProvider.overrideWithValue(state),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('showing: the banner has it', () async {
      final slot = app(
        await piggy(),
        PiggyBannerState.ready,
      ).read(morningPiggySlotProvider);
      expect(slot, isNotNull);
    });

    test('hidden from the start: the street takes it', () async {
      final slot = app(
        await piggy(),
        PiggyBannerState.hidden,
      ).read(morningPiggySlotProvider);
      expect(slot, isNull);
    });

    test('hidden by this run\'s ad: the space stays', () async {
      final service = await piggy();
      await service.watch();
      final slot = app(
        service,
        PiggyBannerState.hidden,
      ).read(morningPiggySlotProvider);
      expect(slot, isNotNull);
    });
  });
}
