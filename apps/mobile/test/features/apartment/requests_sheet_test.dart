// The family requests (specs/015-m10-apartment-story, contracts/apartment.md
// "Family requests", T112): done rows first with «خد», open rows with their
// condition, a missed request absent, the claim's collapse and toast online
// and offline, the badge dropping, the empty state, the row sentences, and
// the three ways out.
import 'package:content_models/content_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/bootstrap/app.dart' show appLocale;
import 'package:wassal/core/content/domain/story_characters.dart';
import 'package:wassal/core/economy/economy_providers.dart';
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/core/l10n/number_formatter.dart';
import 'package:wassal/core/sync/server_status.dart';
import 'package:wassal/core/theme/components/overlays.dart';
import 'package:wassal/features/apartment/presentation/requests_sheet.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

import '../../helpers/lines.dart';
import '../../helpers/progress.dart';
import '../../helpers/routing.dart';
import '../../helpers/synthetic_packs.dart';

const _numbers = NumberFormatter(DigitStyle.arabicIndic);

late AppLocalizations _l10n;

/// The salon with the red curtain in (its request is done), the nish in
/// another style (its request is missed) and the chandelier not bought (its
/// request is open).
const _owned = {microOld, shabka, salonNish, salonSitara};
const _styles = {'salon.nish': 'classic', 'salon.sitara': 'red'};

const _done = 'req_sitara_red';
const _open = 'req_nagfa_crystal';
const _missed = 'req_nish_crystal';

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  Set<(SkuKind, String)> owned = _owned,
  Map<String, String> styles = _styles,
  ServerStatusState serverStatus = const ServerStatusState(),
  String location = '/apartment/requests',
  double textScale = 1.0,
}) async => (await pumpLinesApp(
  tester,
  pack: artboardSalon(),
  location: location,
  serverStatus: serverStatus,
  textScale: textScale,
  state: playerState(stars: hayDone, owned: owned, styles: styles),
)).$1;

FamilyRequest _request(String id) =>
    artboardSalonContent().familyRequests.firstWhere((r) => r.requestId == id);

String _asker(FamilyRequest r) =>
    _l10n.sceneSpeaker(storyCharacterArt(r.character));

void main() {
  setUpAll(() async {
    _l10n = await AppLocalizations.delegate.load(appLocale);
  });

  testWidgets('done first: the happy face, «خلص · +{n} بونات» and «خد»; open '
      'next: its condition and «+{n} بون», no button', (tester) async {
    await _pump(tester);
    final done = _request(_done);
    final open = _request(_open);

    expect(find.text(done.text.arEg), findsOneWidget);
    expect(
      find.text(_l10n.requestsDone(_numbers.integer(done.rewardBonat))),
      findsOneWidget,
    );
    expect(find.byKey(RequestsSheet.claimKey(_done)), findsOneWidget);
    expect(find.text(_l10n.requestsClaim), findsOneWidget);

    expect(find.text(open.text.arEg), findsOneWidget);
    expect(
      find.text(_l10n.requestsReward(_numbers.integer(open.rewardBonat))),
      findsOneWidget,
    );
    expect(
      find.text(_l10n.requestConditionVariant('النجفة', 'كريستال')),
      findsOneWidget,
    );
    expect(find.byKey(RequestsSheet.claimKey(_open)), findsNothing);

    // Done above open.
    expect(
      tester.getTopLeft(find.byKey(RequestsSheet.rowKey(_done))).dy,
      lessThan(tester.getTopLeft(find.byKey(RequestsSheet.rowKey(_open))).dy),
    );
  });

  testWidgets('a missed request is not listed', (tester) async {
    await _pump(tester);
    expect(find.byKey(RequestsSheet.rowKey(_missed)), findsNothing);
    expect(find.text(_request(_missed).text.arEg), findsNothing);
  });

  testWidgets('a request with no style named reads «اشتري {item}»', (
    tester,
  ) async {
    final pack = artboardSalon();
    final requests = pack['family_requests']! as List<Object?>;
    (requests.firstWhere(
              (r) => (r! as Map<String, Object?>)['request_id'] == _open,
            )!
            as Map<String, Object?>)
        .remove('variant_id');
    await pumpLinesApp(
      tester,
      pack: pack,
      location: '/apartment/requests',
      state: playerState(stars: hayDone, owned: _owned, styles: _styles),
    );
    expect(find.text(_l10n.requestCondition('النجفة')), findsOneWidget);
  });

  testWidgets('each row reads as one sentence', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester);
    final done = _request(_done);
    final open = _request(_open);
    expect(
      find.bySemanticsLabel(
        _l10n.requestsRowA11y(
          _asker(done),
          done.text.arEg,
          _l10n.requestConditionVariant('الستارة', 'أحمر'),
          _numbers.integer(done.rewardBonat),
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        _l10n.requestsRowA11y(
          _asker(open),
          open.text.arEg,
          _l10n.requestConditionVariant('النجفة', 'كريستال'),
          _numbers.integer(open.rewardBonat),
        ),
      ),
      findsOneWidget,
    );
    semantics.dispose();
  });

  group('«خد»', () {
    testWidgets('online: the row collapses over 200 ms, the toast says it is '
        'on its way, and the balance waits for the sync', (tester) async {
      final container = await _pump(tester);
      final bonat = container.read(economyViewProvider).bonat;
      await tester.tap(find.byKey(RequestsSheet.claimKey(_done)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      // Collapsing: the row is still there.
      expect(find.byKey(RequestsSheet.rowKey(_done)), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(RequestsSheet.rowKey(_done)), findsNothing);
      // The toast, and the apartment's pending chip behind the sheet (its two
      // lines, «+٥ بون» over «في الطريق»), which
      // carries the same sum until the sync (contracts/apartment.md).
      expect(
        find.text(
          _l10n.requestsClaimToast(
            _numbers.integer(_request(_done).rewardBonat),
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          _l10n.pendingRewards(_numbers.integer(_request(_done).rewardBonat)),
        ),
        findsOneWidget,
      );
      final view = container.read(economyViewProvider);
      expect(view.requestsClaimed, {_done});
      expect(view.bonat, bonat, reason: 'the server pays (constitution IV)');
      // The open one stays.
      expect(find.byKey(RequestsSheet.rowKey(_open)), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 4));
    });

    testWidgets('offline: «توصل مع النت»', (tester) async {
      await _pump(
        tester,
        serverStatus: const ServerStatusState(reach: Reach.offline),
      );
      await tester.tap(find.byKey(RequestsSheet.claimKey(_done)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.text(
          _l10n.requestsClaimToastOffline(
            _numbers.integer(_request(_done).rewardBonat),
          ),
        ),
        findsOneWidget,
      );
      await tester.pumpAndSettle(const Duration(seconds: 4));
    });

    testWidgets('reduced motion: the row fades without closing its height', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await _pump(tester);
      final openTop = tester
          .getTopLeft(find.byKey(RequestsSheet.rowKey(_open)))
          .dy;
      await tester.tap(find.byKey(RequestsSheet.claimKey(_done)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        tester.getTopLeft(find.byKey(RequestsSheet.rowKey(_open))).dy,
        openTop,
        reason: 'the rows below stay put while it fades',
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byKey(RequestsSheet.rowKey(_done)), findsNothing);
      await tester.pumpAndSettle(const Duration(seconds: 4));
    });

    testWidgets('the rooms view\'s badge drops with the list', (tester) async {
      await _pump(tester, location: '/apartment');
      Finder badge(int n) => find.text(_numbers.integer(n));
      final button = find.bySemanticsLabel(
        _l10n.aptRoomsRequestsA11y(_numbers.integer(2)),
      );
      expect(button, findsOneWidget, reason: 'the done and the open');
      await tester.tap(button);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(RequestsSheet.claimKey(_done)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(RequestsSheet.closeKey));
      await tester.pumpAndSettle(const Duration(seconds: 4));
      expect(
        find.bySemanticsLabel(_l10n.aptRoomsRequestsA11y(_numbers.integer(1))),
        findsOneWidget,
      );
      expect(badge(1), findsWidgets);
    });
  });

  testWidgets('nothing open or done: the empty state', (tester) async {
    await _pump(tester, owned: const {}, styles: const {});
    expect(find.byKey(RequestsSheet.emptyKey), findsOneWidget);
    expect(find.text(_l10n.requestsEmpty), findsOneWidget);
    expect(find.text(_l10n.requestsClaim), findsNothing);
  });

  testWidgets('the header: title, line, and the sheet is named', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.text(_l10n.requestsTitle), findsOneWidget);
    expect(find.text(_l10n.requestsSubtitle), findsOneWidget);
    expect(find.byType(AppSheet), findsOneWidget);
  });

  group('closes to the apartment', () {
    testWidgets('by ✕', (tester) async {
      final container = await _pump(tester, location: '/apartment');
      await tester.tap(
        find.bySemanticsLabel(_l10n.aptRoomsRequestsA11y(_numbers.integer(2))),
      );
      await tester.pumpAndSettle();
      expect(find.byType(RequestsSheet), findsOneWidget);
      await tester.tap(find.byKey(RequestsSheet.closeKey));
      await tester.pumpAndSettle();
      expect(find.byType(RequestsSheet), findsNothing);
      expect(locationOf(container), '/apartment');
    });

    testWidgets('by the phone\'s back', (tester) async {
      final container = await _pump(tester);
      await pressBack(tester);
      await tester.pumpAndSettle();
      expect(find.byType(RequestsSheet), findsNothing);
      expect(locationOf(container), '/apartment');
    });

    testWidgets('by a swipe down', (tester) async {
      final container = await _pump(tester);
      await tester.drag(find.byType(AppSheet), const Offset(0, 600));
      await tester.pumpAndSettle();
      expect(find.byType(RequestsSheet), findsNothing);
      expect(locationOf(container), '/apartment');
    });
  });

  testWidgets('at text scale 1.3 the sheet draws without overflow', (
    tester,
  ) async {
    await _pump(tester, textScale: 1.3);
    expect(tester.takeException(), isNull);
    expect(find.text(_l10n.requestsTitle), findsOneWidget);
    expect(find.byKey(RequestsSheet.claimKey(_done)), findsOneWidget);
  });
}
