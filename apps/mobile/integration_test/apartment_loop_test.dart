// The loop from الشقة (specs/015-m10-apartment-story, quickstart §5, SC-001,
// SC-003, SC-009), offline, for a chapter-3 player with enough coins and the
// card setting on «دايمًا»: the goal view's «اشتري الشبكة» spends the price
// once and opens the story trip's card, whose close lands on the rooms view;
// the salon's four pieces from their sheets, one in the style a request
// names; the request's «خد», which says it is on its way while the BONAT
// balance waits for the server; the last piece's RoomDone with its reward
// «في الطريق» and «شوف المشهد» playing the goal scene, recorded once; then the
// timeline with chapter 4 done and the album with every scene unlocked but
// the one that waits for a trip. It also times the tab, a sheet and the
// timeline from the tap to their full content (each under 0.5 s) and the
// first panel (under 1 s). Headless:
//
//   fvm flutter test integration_test/apartment_loop_test.dart -d flutter-tester
//
// or on a device with `--flavor dev`.
import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wassal/bootstrap/app.dart' show appLocale;
import 'package:wassal/core/content/content_providers.dart';
import 'package:wassal/core/config/tunable.dart';
import 'package:wassal/core/content/pack_content_source.dart';
import 'package:wassal/core/economy/domain/op.dart';
import 'package:wassal/core/economy/economy_providers.dart';
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/l10n/number_formatter.dart';
import 'package:wassal/core/progress/application/player_progress_provider.dart';
import 'package:wassal/core/progress/domain/story.dart';
import 'package:wassal/core/theme/components/nav.dart';
import 'package:wassal/core/theme/components/pressable.dart';
import 'package:wassal/features/apartment/domain/chapter_rows.dart';
import 'package:wassal/features/apartment/presentation/chapters_page.dart';
import 'package:wassal/features/apartment/presentation/goal_view.dart';
import 'package:wassal/features/apartment/presentation/piece_sheet.dart';
import 'package:wassal/features/apartment/presentation/requests_sheet.dart';
import 'package:wassal/features/apartment/presentation/room_done_dialog.dart';
import 'package:wassal/features/apartment/presentation/room_scene.dart';
import 'package:wassal/features/home/application/checkpoint.dart';
import 'package:wassal/features/pre_trip/application/card_mode_provider.dart';
import 'package:wassal/features/pre_trip/presentation/pre_trip_card.dart';
import 'package:wassal/features/story/domain/album.dart';
import 'package:wassal/features/story/presentation/album_page.dart';
import 'package:wassal/features/story/presentation/scene_viewer_page.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

import '../test/helpers/content.dart';
import '../test/helpers/economy.dart';
import '../test/helpers/lines.dart';
import '../test/helpers/memory_settings_store.dart';
import '../test/helpers/progress.dart';
import '../test/helpers/pump_app.dart';
import '../test/helpers/synthetic_packs.dart';
import '../test/helpers/trip.dart';
import 'trip_helpers.dart';

/// SC-009: from the tap to full content.
const _openBudget = Duration(milliseconds: 500);

/// SC-009: from the tap to a scene's first panel.
const _panelBudget = Duration(seconds: 1);

/// What the player holds in BONAT: the loop never changes it (SC-003).
const _bonat = 7;

const _numbers = NumberFormatter(DigitStyle.arabicIndic);

/// The release draft's line_hay, every trip finished: chapter 1 done.
final _hayDone = {
  for (var i = 1; i <= 20; i++) 'line_hay.${i.toString().padLeft(2, '0')}': 3,
};

/// A checkpoint that never holds (M11's interstitial comes later).
final class _Open implements BetweenTripsCheckpoint {
  @override
  Future<void> pass() async {}
}

/// Taps [finder] once it can be hit.
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await pumpUntil(tester, () => finder.evaluate().isNotEmpty);
  await tester.ensureVisible(finder);
  await pumpUntil(tester, () => finder.hitTestable().evaluate().isNotEmpty);
  await tester.tap(finder);
}

/// Real time from a tap on [control] until [shown] can be hit.
Future<Duration> _timeOpen(
  WidgetTester tester,
  Finder control,
  Finder shown,
) async {
  await pumpUntil(tester, () => control.evaluate().isNotEmpty);
  await tester.ensureVisible(control);
  await pumpUntil(tester, () => control.hitTestable().evaluate().isNotEmpty);
  final watch = Stopwatch()..start();
  await tester.tap(control);
  await pumpUntil(tester, () => shown.hitTestable().evaluate().isNotEmpty);
  return watch.elapsed;
}

/// The operations of [type] still waiting for the sync.
Future<List<LedgerOp>> _pending(
  WidgetTester tester,
  TestEconomy economy,
  OpType type,
) async {
  final all = await tester.runAsync(economy.service.pendingOps);
  return [
    for (final row in all!)
      if (row.op.type == type) row,
  ];
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(appLocale);
  });

  testWidgets('الشقة → the shabka → its card → the salon → «خد» → RoomDone → '
      'the scene → the timeline → the album, offline', (tester) async {
    final json = storyShaped();
    final content = PackContentSource(Pack.fromJson(json));
    final economy = await testEconomy(
      content: content,
      // Chapters 1 and 2 done, saving for the shabka (6,000) and the salon's
      // four pieces (4,700).
      firstState: playerState(
        jenehat: 12000,
        bonat: _bonat,
        stars: _hayDone,
        owned: {microOld},
      ),
    );
    final container = await pumpWassalApp(
      tester,
      settleBoot: false,
      settle: false,
      content: contentTestOverrides(
        assets: bundledAssetsFor(encodePackFile(json)),
      ),
      economy: economyOverridesOf(economy),
      settingsStore: MemorySettingsStore({
        DigitStyleNotifier.key: DigitStyle.arabicIndic.wire,
        PreTripCardModeNotifier.key: PreTripCardMode.always.wire,
      }),
      overrides: [betweenTripsCheckpointProvider.overrideWithValue(_Open())],
    );
    await pumpUntil(tester, () => currentLocation(tester) == '/home');

    // 1. «الشقة» opens on the goal view, ready, within SC-009.
    final tab = await _timeOpen(
      tester,
      find.byKey(BottomNav.cellKey(2)),
      find.byKey(ApartmentGoalView.buyKey),
    );
    expect(tab, lessThan(_openBudget));
    expect(currentLocation(tester), '/apartment');

    // 2. «اشتري الشبكة»: the price once, and the story trip's card opens.
    await _tap(tester, find.byKey(ApartmentGoalView.buyKey));
    await tester.tap(find.byKey(ApartmentGoalView.buyKey), warnIfMissed: false);
    await pumpUntil(
      tester,
      () => currentLocation(tester) == '/apartment/pre-trip/line_gamaa.18',
    );
    var view = container.read(economyViewProvider);
    expect(view.jenehat, 6000);
    expect(view.owns(SkuKind.chapter, 'ch3_shabka'), isTrue);
    expect(
      await _pending(tester, economy, OpType.spendJenehat),
      hasLength(1),
      reason: 'one spend, kept to sync',
    );

    // Closing the card lands on the rooms view (SC-001).
    await _tap(tester, find.byKey(PreTripCard.closeKey));
    await pumpUntil(tester, () => currentLocation(tester) == '/apartment');
    await pumpUntil(
      tester,
      () => find.byType(RoomScene).hitTestable().evaluate().isNotEmpty,
    );

    // 3. The salon's pieces from their sheets, the نيش in the crystal style
    // its request names.
    Future<Duration> buyPiece(String name, {String? style}) async {
      final opened = await _timeOpen(
        tester,
        find.text(name).last,
        find.byKey(PieceSheet.buyKey),
      );
      if (style != null) {
        await _tap(
          tester,
          find
              .byWidgetPredicate(
                (w) => w is Pressable && w.semanticLabel == style,
              )
              .first,
        );
        // The sheet draws the chosen style before «اشتري» buys it.
        await tester.pump();
      }
      await _tap(tester, find.byKey(PieceSheet.buyKey));
      return opened;
    }

    final sheet = await buyPiece('النيش', style: 'كريستال');
    expect(sheet, lessThan(_openBudget));
    await pumpUntil(tester, () => currentLocation(tester) == '/apartment');
    view = container.read(economyViewProvider);
    expect(view.jenehat, 5250);
    expect(view.variantOf('salon.nish'), 'crystal');

    // 4. The request's «خد»: «في الطريق», and the balance waits (SC-003).
    await _tap(tester, find.text(l10n.aptRoomsRequests));
    await pumpUntil(
      tester,
      () => currentLocation(tester) == '/apartment/requests',
    );
    await _tap(tester, find.byKey(RequestsSheet.claimKey('req_nish_crystal')));
    await pumpUntil(
      tester,
      () => container
          .read(economyViewProvider)
          .requestsClaimed
          .contains('req_nish_crystal'),
    );
    expect(
      find.text(l10n.requestsClaimToast(_numbers.integer(5))),
      findsWidgets,
    );
    expect(container.read(economyViewProvider).bonat, _bonat);
    await _tap(tester, find.byKey(RequestsSheet.closeKey));
    await pumpUntil(tester, () => currentLocation(tester) == '/apartment');

    // 5. The other three pieces. The last one finishes the room.
    for (final name in ['الستارة', 'الأنتريه']) {
      await buyPiece(name);
      await pumpUntil(tester, () => currentLocation(tester) == '/apartment');
    }
    await buyPiece('النجفة');
    await pumpUntil(
      tester,
      () => find.byType(RoomDoneDialog).evaluate().isNotEmpty,
    );
    view = container.read(economyViewProvider);
    expect(view.jenehat, 1300);
    expect(
      find.text(l10n.roomDonePending),
      findsWidgets,
      reason: 'the reward is on its way',
    );
    expect(view.bonat, _bonat, reason: 'the server pays (constitution IV)');

    final panel = await _timeOpen(
      tester,
      find.byKey(RoomDoneDialog.ctaKey),
      find.byKey(SceneViewerPage.panelKey),
    );
    expect(panel, lessThan(_panelBudget));
    expect(currentLocation(tester), startsWith('/story/scene/family_visit'));
    for (
      var i = 0;
      i < 12 && find.byKey(SceneViewerPage.continueKey).evaluate().isEmpty;
      i++
    ) {
      await tester.tap(find.byKey(SceneViewerPage.panelKey));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 600)),
      );
      await tester.pump();
    }
    await _tap(tester, find.byKey(SceneViewerPage.continueKey));
    await pumpUntil(tester, () => currentLocation(tester) == '/apartment');
    expect(container.read(economyViewProvider).scenesSeen['ch4_salon'], {
      'family_visit',
    });
    final recorded = await _pending(tester, economy, OpType.storyProgress);
    expect(
      recorded.where((row) => row.op.string('scene_id') == 'family_visit'),
      hasLength(1),
      reason: 'the scene is recorded once',
    );

    // 6. The timeline: chapters 1 to 4 done, within SC-009.
    final timeline = await _timeOpen(
      tester,
      find.text('كل الفصول'),
      find.byKey(ChaptersPage.rowKey(ChapterId.ch4Salon)),
    );
    expect(timeline, lessThan(_openBudget));
    expect(currentLocation(tester), '/apartment/chapters');
    final rows = chapterRows(
      container.read(contentSourceProvider),
      container.read(playerProgressProvider),
      jenehat: container.read(economyViewProvider).jenehat,
    );
    expect(rows.take(4), everyElement(isA<DoneRow>()));

    // 7. The album counts every scene, the one that waits for its trip aside.
    await _tap(tester, find.byKey(ChaptersPage.albumKey));
    await pumpUntil(tester, () => currentLocation(tester) == '/story/album');
    final (cards, unlocked, total) = album(
      container.read(contentSourceProvider),
      container.read(playerProgressProvider),
    );
    expect(total, scenesInStoryOrder(content).length);
    expect(unlocked, total - 1);
    expect(cards.whereType<LockedCard>().single.sceneId, 'the_fatha');
    await pumpUntil(
      tester,
      () => find.byKey(AlbumPage.countKey).hitTestable().evaluate().isNotEmpty,
    );
    expect(
      find.text(
        l10n.albumCount(_numbers.integer(unlocked), _numbers.integer(total)),
      ),
      findsOneWidget,
    );
  });
}
