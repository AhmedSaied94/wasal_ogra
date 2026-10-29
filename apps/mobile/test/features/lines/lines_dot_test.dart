// The «new» dot on «الخطوط» (specs/014-m09-lines-vehicles, US6, FR-041):
// shown after news while away, cleared on opening Lines, still cleared
// after a restart, never for a purchase made on Lines, and not on a first
// read.
import 'package:content_models/content_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/economy/domain/economy_state.dart';
import 'package:wassal/core/routing/new_dot_providers.dart';
import 'package:wassal/core/routing/router.dart';
import 'package:wassal/core/routing/routes.dart';
import 'package:wassal/features/lines/application/lines_seen.dart';
import 'package:wassal/features/lines/presentation/vehicle_sheet.dart';

import '../../helpers/lines.dart';
import '../../helpers/memory_settings_store.dart';

bool _dot(ProviderContainer c) => c.read(newDotProvider(Section.lines));

void main() {
  testWidgets('a first read takes the news as seen: no dot', (tester) async {
    final store = MemorySettingsStore();
    final (container, _) = await pumpLinesApp(
      tester,
      state: playerState(jenehat: 2000),
      location: '/home',
      settingsStore: store,
    );
    expect(_dot(container), isFalse);
    expect(store.values[LinesSeenNotifier.key], 'vehicle:micro_old');
  });

  testWidgets('news not seen shows the dot from Home; opening Lines clears '
      'it; a restart keeps it cleared', (tester) async {
    // A stored seen set without the microbus: it is news.
    final store = MemorySettingsStore({LinesSeenNotifier.key: 'line:x'});
    final (container, _) = await pumpLinesApp(
      tester,
      state: playerState(jenehat: 2000),
      location: '/home',
      settingsStore: store,
    );
    expect(_dot(container), isTrue);
    container.read(routerProvider).go('/lines');
    await tester.pumpAndSettle();
    expect(_dot(container), isFalse);
    final (again, _) = await pumpLinesApp(
      tester,
      state: playerState(jenehat: 2000),
      location: '/home',
      settingsStore: store,
    );
    expect(_dot(again), isFalse);
  });

  testWidgets('a purchase made on Lines raises no dot', (tester) async {
    final store = MemorySettingsStore({LinesSeenNotifier.key: ''});
    final (container, _) = await pumpLinesApp(
      tester,
      state: playerState(jenehat: 1600),
      location: '/lines/vehicle/micro_old',
      settingsStore: store,
    );
    await tester.tap(find.byKey(VehicleSheet.buyKey));
    await tester.pumpAndSettle();
    expect(locationOf(container), '/lines');
    // The microbus opened خط الجامعة: news, seen as it happened.
    expect(container.read(linesNewsKeysProvider), contains('line:line_gamaa'));
    expect(_dot(container), isFalse);
    container.read(routerProvider).go('/home');
    await tester.pumpAndSettle();
    expect(_dot(container), isFalse);
    expect(
      LinesSeenNotifier.decode(store.values[LinesSeenNotifier.key]!),
      contains('line:line_gamaa'),
    );
  });

  testWidgets('news that comes while away is seen on the return to the tab, '
      'and the dot stays off', (tester) async {
    final store = MemorySettingsStore({LinesSeenNotifier.key: ''});
    final (container, economy) = await pumpLinesApp(
      tester,
      state: playerState(jenehat: 2000),
      settingsStore: store,
    );
    container.read(routerProvider).go('/home');
    await tester.pumpAndSettle();
    // Away, the microbus is bought (as Home's goal card will): خط الجامعة
    // opens, news Lines hasn't shown.
    await economy.service.buy(
      economy.service.newRequestId(),
      kind: SkuKind.vehicle,
      skuId: 'micro_old',
    );
    await tester.pumpAndSettle();
    // The dot is on before any return to Lines (T108).
    expect(_dot(container), isTrue);
    final news = container.read(linesNewsKeysProvider);
    expect(news, contains('line:line_gamaa'));
    expect(
      LinesSeenNotifier.decode(store.values[LinesSeenNotifier.key]!),
      isNot(contains('line:line_gamaa')),
    );
    container.read(routerProvider).go('/lines');
    await tester.pumpAndSettle();
    expect(
      LinesSeenNotifier.decode(store.values[LinesSeenNotifier.key]!),
      containsAll(news),
    );
    container.read(routerProvider).go('/home');
    await tester.pumpAndSettle();
    expect(_dot(container), isFalse);
  });

  testWidgets('news that goes away and comes back raises the dot again '
      '(T101)', (tester) async {
    final store = MemorySettingsStore();
    final (container, economy) = await pumpLinesApp(
      tester,
      state: playerState(jenehat: 2000),
      location: '/home',
      settingsStore: store,
    );
    // The microbus is affordable, and its news is seen on the first read.
    expect(_dot(container), isFalse);
    EconomyState state(int jenehat) =>
        EconomyState.newPlayer(fuelMax: 5, nowMs: 0).copyWith(jenehat: jenehat);
    // A sync spends below its price: the news goes away, and so does its
    // seen key.
    await economy.service.replaceFromServer(
      state(1200),
      playerId: 'test-player',
      stateVersion: 2,
    );
    await tester.pumpAndSettle();
    expect(container.read(linesNewsKeysProvider), isEmpty);
    expect(
      LinesSeenNotifier.decode(store.values[LinesSeenNotifier.key]!),
      isEmpty,
    );
    // The price earned back while on Home: it is news again, so the dot is
    // on.
    await economy.service.replaceFromServer(
      state(2000),
      playerId: 'test-player',
      stateVersion: 3,
    );
    await tester.pumpAndSettle();
    expect(
      container.read(linesNewsKeysProvider),
      contains('vehicle:micro_old'),
    );
    expect(_dot(container), isTrue);
  });
}
