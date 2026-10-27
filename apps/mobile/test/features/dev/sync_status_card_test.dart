import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/bootstrap/flavor.dart';
import 'package:wassal/core/economy/economy_providers.dart';
import 'package:wassal/core/network/api_client.dart';
import 'package:wassal/core/routing/router.dart';
import 'package:wassal/features/dev/sync_status_card.dart';

import '../../helpers/account.dart';
import '../../helpers/fake_api.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/sync.dart';

// Internal builds' sync card (specs/011-m06-identity-sync, US6), in the
// whole app: a signed-in player, an operation recorded, and «sync now».

Future<(ProviderContainer, FakeApi)> _pump(
  WidgetTester tester, {
  Flavor flavor = Flavor.dev,
}) async {
  final api = FakeApi(fallback: unreachable)
    ..reply('POST', ApiPaths.anonymous, [
      apiOk(tokenJson(providers: ['google'])),
    ])
    ..always(
      'POST',
      ApiPaths.sync,
      (ApiRequest r) => syncAnswerFor(r, stateVersion: 6),
    );
  final container = await pumpWassalApp(
    tester,
    flavor: flavor,
    account: accountTestOverrides(api: api),
  );
  final card = find.byType(SyncStatusCard);
  if (card.evaluate().isNotEmpty) {
    await tester.ensureVisible(card);
    await tester.pumpAndSettle();
  }
  return (container, api);
}

/// The card's value for [label].
String _value(WidgetTester tester, String label) {
  final row = find
      .ancestor(
        of: find.descendant(
          of: find.byType(SyncStatusCard),
          matching: find.text(label),
        ),
        matching: find.byType(Row),
      )
      .first;
  return tester
      .widgetList<Text>(find.descendant(of: row, matching: find.byType(Text)))
      .last
      .data!;
}

String _allText(WidgetTester tester) => [
  for (final text in tester.widgetList<Text>(
    find.descendant(
      of: find.byType(SyncStatusCard),
      matching: find.byType(Text),
    ),
  ))
    text.data ?? '',
].join('\n');

void main() {
  testWidgets('the account, the queue and the last pass', (tester) async {
    await _pump(tester);

    expect(_value(tester, 'account'), 'active');
    expect(_value(tester, 'player_id'), '${playerIdOf(1).substring(0, 8)}…');
    expect(_value(tester, 'providers'), 'google');
    expect(_value(tester, 'pending'), '0');
    for (final label in [
      'state_version',
      'last_pass',
      'pass_ms',
      'ended_at',
      'last_error',
      'set_aside',
    ]) {
      expect(_value(tester, label), isNotEmpty, reason: label);
    }
  });

  testWidgets('an operation counts, and «sync now» sends it', (tester) async {
    final (container, api) = await _pump(tester);
    final economy = container.read(economyProvider).requireValue;

    await economy.startTrip(economy.newRequestId(), tripId: 'line_hay.01');
    await tester.pumpAndSettle();
    expect(_value(tester, 'pending'), '1');

    await tester.tap(find.byKey(SyncStatusCard.syncNowKey));
    await tester.pumpAndSettle();

    expect(api.to(ApiPaths.sync), hasLength(1));
    expect(api.to(ApiPaths.bootstrap), isNotEmpty, reason: 'forced first');
    expect(_value(tester, 'pending'), '0');
    expect(_value(tester, 'state_version'), '6');
    expect(_value(tester, 'last_pass'), startsWith('done: 1 batches'));
    expect(_value(tester, 'last_error'), 'none');
  });

  testWidgets('no token, install id or whole player id in it', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester);

    final text = _allText(tester);
    for (final secret in [
      'access-1',
      'refresh-1',
      testInstallId.value,
      playerIdOf(1),
    ]) {
      expect(text, isNot(contains(secret)));
      expect(
        find.bySemanticsLabel(RegExp(RegExp.escape(secret))),
        findsNothing,
      );
    }
    semantics.dispose();
  });

  for (final flavor in Flavor.values) {
    final shown = flavor != Flavor.prod;
    testWidgets('${shown ? 'on' : 'not on'} Home in ${flavor.name}', (
      tester,
    ) async {
      final (container, _) = await _pump(tester, flavor: flavor);
      expect(container.read(routerProvider).state.uri.path, '/home');
      expect(
        find.byType(SyncStatusCard),
        shown ? findsOneWidget : findsNothing,
      );
    });
  }
}
