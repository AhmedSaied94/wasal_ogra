// The album (specs/015-m10-apartment-story, contracts/scene-viewer.md "The
// album", T102): the count and the intro, an unlocked card opening its scene
// with `then` the album, a locked card inert and labelled, back to the
// timeline, a replay that queues nothing, and the grid scrolling at 1.3x.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/bootstrap/app.dart' show appLocale;
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/core/l10n/number_formatter.dart';
import 'package:wassal/core/routing/router.dart';
import 'package:wassal/features/story/presentation/album_page.dart';
import 'package:wassal/features/story/presentation/scene_viewer_page.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

import '../../helpers/economy.dart';
import '../../helpers/lines.dart';
import '../../helpers/progress.dart';

const _numbers = NumberFormatter(DigitStyle.arabicIndic);

late AppLocalizations _l10n;

/// Chapters 1 and 2 done, `the_stand` unlocked by `line_hay.03`; the family's
/// visit still locked. The opening is seen.
final _stars = {...hayDone, 'line_hay.03': 1};

Future<(ProviderContainer, TestEconomy)> _open(
  WidgetTester tester, {
  double textScale = 1.0,
  Size? size,
}) => pumpLinesApp(
  tester,
  pack: samplePackJsonForLines(),
  location: '/story/album',
  textScale: textScale,
  size: size,
  state: playerState(
    stars: _stars,
    owned: {microOld},
    scenesSeen: const {
      'ch1_first_job': {'opening'},
    },
  ),
);

void main() {
  setUpAll(() async {
    _l10n = await AppLocalizations.delegate.load(appLocale);
  });

  testWidgets('the count chip and the intro', (tester) async {
    await _open(tester);
    // Three scenes unlocked of the sample's four.
    expect(
      find.text(_l10n.albumCount(_numbers.integer(3), _numbers.integer(4))),
      findsOneWidget,
    );
    expect(find.text(_l10n.albumTitle), findsOneWidget);
    expect(find.text(_l10n.albumIntro), findsOneWidget);
  });

  testWidgets('one card per scene, in story order', (tester) async {
    await _open(tester);
    for (final id in ['opening', 'the_stand', 'father_visit', 'family_visit']) {
      expect(find.byKey(AlbumPage.cardKey(id)), findsOneWidget, reason: id);
    }
    // Story order: the first card sits above and at the start side of the
    // second, which is not below it.
    final first = tester.getTopRight(find.byKey(AlbumPage.cardKey('opening')));
    final second = tester.getTopLeft(
      find.byKey(AlbumPage.cardKey('the_stand')),
    );
    expect(first.dy, second.dy);
    expect(first.dx, greaterThan(second.dx));
  });

  testWidgets('the cards read as one sentence each', (tester) async {
    final semantics = tester.ensureSemantics();
    await _open(tester);
    String label(String id) =>
        tester.getSemantics(find.byKey(AlbumPage.cardKey(id))).label;
    expect(
      label('opening'),
      _l10n.albumCardA11y('unlocked', _numbers.integer(1), 'المفتاح'),
    );
    expect(
      label('family_visit'),
      _l10n.albumCardA11y('locked', _numbers.integer(4), 'العيلة في الصالون'),
    );
    semantics.dispose();
  });

  testWidgets('an unlocked card opens its scene, back to the album', (
    tester,
  ) async {
    await _open(tester);
    await tester.tap(find.byKey(AlbumPage.cardKey('the_stand')));
    await tester.pumpAndSettle();
    final viewer = tester.widget<SceneViewerPage>(find.byType(SceneViewerPage));
    expect(viewer.sceneId, 'the_stand');
    expect(viewer.then, '/story/album');
  });

  testWidgets('a locked card is inert', (tester) async {
    final (container, _) = await _open(tester);
    await tester.tap(find.byKey(AlbumPage.cardKey('family_visit')));
    await tester.pumpAndSettle();
    expect(locationOf(container), '/story/album');
    expect(find.text(_l10n.albumLocked), findsOneWidget);
  });

  testWidgets('a replay of a seen scene queues nothing', (tester) async {
    final (container, economy) = await _open(tester);
    final before = economy.service.pendingCount;
    await tester.tap(find.byKey(AlbumPage.cardKey('opening')));
    await tester.pumpAndSettle();
    expect(find.byType(SceneViewerPage), findsOneWidget);
    // Through every panel, then «كمّل» on the last.
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byKey(SceneViewerPage.panelKey));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(SceneViewerPage.continueKey));
    await tester.pumpAndSettle();
    expect(economy.service.pendingCount, before);
    // `then`: the album again.
    expect(locationOf(container), '/story/album');
  });

  testWidgets('back goes to the timeline', (tester) async {
    final (container, _) = await _open(tester);
    await tester.tap(find.bySemanticsLabel(_l10n.backLabel));
    await tester.pumpAndSettle();
    expect(locationOf(container), '/apartment/chapters');
  });

  testWidgets('back pops to the timeline it came from', (tester) async {
    final (container, _) = await _open(tester);
    container.read(routerProvider).go('/apartment/chapters');
    await tester.pumpAndSettle();
    unawaited(container.read(routerProvider).push('/story/album'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel(_l10n.backLabel));
    await tester.pumpAndSettle();
    expect(locationOf(container), '/apartment/chapters');
  });

  testWidgets('the grid scrolls at 1.3x on a short phone', (tester) async {
    await _open(tester, textScale: 1.3, size: const Size(360, 640));
    await tester.scrollUntilVisible(
      find.byKey(AlbumPage.cardKey('family_visit')),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(AlbumPage.cardKey('family_visit')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
