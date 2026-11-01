// The timeline (specs/015-m10-apartment-story, contracts/scene-viewer.md "The
// timeline", T101): the rows and their sentences, «شوف المشهد» and the album
// pill, the rail filled to the current node and animating once, back, a
// chapter the pack lacks, and seven rows scrolling at 1.3x.
import 'dart:async';

import 'package:content_models/content_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/bootstrap/app.dart' show appLocale;
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/core/l10n/number_formatter.dart';
import 'package:wassal/core/routing/router.dart';
import 'package:wassal/features/apartment/presentation/chapters_page.dart';
import 'package:wassal/features/story/presentation/album_page.dart';
import 'package:wassal/features/story/presentation/scene_viewer_page.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

import '../../helpers/lines.dart';
import '../../helpers/progress.dart';
import '../../helpers/synthetic_packs.dart';

const _numbers = NumberFormatter(DigitStyle.arabicIndic);

late AppLocalizations _l10n;

/// The salon with two of its four pieces: chapters 1 to 3 done, 4 current.
const _atSalon = {microOld, shabka, salonNish, salonSitara};

Future<ProviderContainer> _open(
  WidgetTester tester, {
  Map<String, Object?>? pack,
  double textScale = 1.0,
  Size? size,
  String location = '/apartment/chapters',
  Set<(SkuKind, String)> owned = _atSalon,
}) async {
  final (container, _) = await pumpLinesApp(
    tester,
    pack: pack ?? artboardSalon(),
    location: location,
    textScale: textScale,
    size: size,
    state: playerState(
      stars: hayDone,
      owned: owned,
      styles: const {'salon.nish': 'classic', 'salon.sitara': 'plain'},
    ),
  );
  return container;
}

String _name(String id) => artboardSalonContent().chapters
    .firstWhere((c) => c.chapterId.name == id)
    .title
    .arEg;

/// The rail's fill under row [index], as the page drew it.
double _fill(WidgetTester tester, int index) {
  final finder = find.byKey(ChaptersPage.railFillKey(index));
  return finder.evaluate().isEmpty ? 0 : tester.getSize(finder).height;
}

void main() {
  setUpAll(() async {
    _l10n = await AppLocalizations.delegate.load(appLocale);
  });

  testWidgets('seven rows by the glossary, each read as one sentence', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _open(tester);
    String sentence(ChapterId id) =>
        tester.getSemantics(find.byKey(ChaptersPage.rowKey(id))).label;
    String n(int i) => _numbers.integer(i);

    expect(
      sentence(ChapterId.ch1FirstJob),
      _l10n.chaptersRowA11y('done', n(1), _name('ch1FirstJob'), ''),
    );
    expect(
      sentence(ChapterId.ch3Shabka),
      _l10n.chaptersRowA11y('done', n(3), _name('ch3Shabka'), ''),
    );
    expect(
      sentence(ChapterId.ch4Salon),
      _l10n.chaptersRowA11y(
        'current',
        n(4),
        _name('ch4Salon'),
        _l10n.chaptersItemsChip(n(2), n(4)),
      ),
    );
    expect(
      sentence(ChapterId.ch5Kitchen),
      _l10n.chaptersRowA11y('locked', n(5), _name('ch5Kitchen'), ''),
    );
    for (final id in ChapterId.values) {
      expect(
        find.byKey(ChaptersPage.rowKey(id)),
        findsOneWidget,
        reason: '$id',
      );
    }
    semantics.dispose();
  });

  testWidgets('the current row: «الفصل ٤ · دلوقتي», the pieces and the scene', (
    tester,
  ) async {
    await _open(tester);
    expect(
      find.text(_l10n.chaptersCurrent(_numbers.integer(4))),
      findsOneWidget,
    );
    expect(
      find.text(
        _l10n.chaptersItemsChip(_numbers.integer(2), _numbers.integer(4)),
      ),
      findsOneWidget,
    );
    final content = artboardSalonContent();
    final names = [
      for (final item in content.itemsOf(RoomId.salon)) item.name.arEg,
    ]..sort();
    final description = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .firstWhere((text) => text.contains(_l10n.chaptersItemSeparator));
    for (final name in names) {
      expect(description, contains(name));
    }
    expect(description, contains('العيلة في الصالون'));
  });

  testWidgets('«شوف المشهد» replays the chapter', (tester) async {
    final container = await _open(tester);
    await tester.tap(find.byKey(ChaptersPage.watchKey(ChapterId.ch1FirstJob)));
    await tester.pumpAndSettle();
    // Pushed over the timeline, so back and «كمّل» return to it.
    final viewer = tester.widget<SceneViewerPage>(find.byType(SceneViewerPage));
    expect(viewer.chapterId, ChapterId.ch1FirstJob);
    expect(viewer.sceneId, isNull);
    expect(container.read(routerProvider).canPop(), isTrue);
  });

  testWidgets('a done chapter without a scene has no button', (tester) async {
    await _open(tester);
    // The sample's chapter 3 has no scene.
    expect(
      find.byKey(ChaptersPage.watchKey(ChapterId.ch3Shabka)),
      findsNothing,
    );
    expect(
      find.byKey(ChaptersPage.watchKey(ChapterId.ch2HerFather)),
      findsOneWidget,
    );
  });

  testWidgets('«ألبوم المشاهد» opens the album', (tester) async {
    final container = await _open(tester);
    await tester.tap(find.byKey(ChaptersPage.albumKey));
    await tester.pumpAndSettle();
    expect(find.byType(AlbumPage), findsOneWidget);
    // Pushed, so the album's back returns here.
    expect(container.read(routerProvider).canPop(), isTrue);
  });

  testWidgets('back goes to the apartment', (tester) async {
    final container = await _open(tester);
    await tester.tap(find.bySemanticsLabel(_l10n.backLabel));
    await tester.pumpAndSettle();
    expect(locationOf(container), '/apartment');
  });

  testWidgets('back pops to where it came from', (tester) async {
    final container = await _open(tester);
    container.read(routerProvider).go('/apartment');
    await tester.pumpAndSettle();
    unawaited(container.read(routerProvider).push('/apartment/chapters'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel(_l10n.backLabel));
    await tester.pumpAndSettle();
    expect(locationOf(container), '/apartment');
  });

  testWidgets('the current and locked rows are inert', (tester) async {
    final container = await _open(tester);
    await tester.tap(find.byKey(ChaptersPage.rowKey(ChapterId.ch4Salon)));
    await tester.tap(find.byKey(ChaptersPage.rowKey(ChapterId.ch5Kitchen)));
    await tester.pumpAndSettle();
    expect(locationOf(container), '/apartment/chapters');
  });

  testWidgets('a chapter the pack lacks is named from the strings', (
    tester,
  ) async {
    await _open(tester, pack: samplePackJsonForLines());
    expect(find.text(_l10n.chapterTeaserName('ch5_kitchen')), findsOneWidget);
    expect(find.text(_l10n.chapterTeaserName('ch6_bedroom')), findsOneWidget);
    expect(find.text(_l10n.chapterTeaserName('ch7_wedding')), findsOneWidget);
  });

  testWidgets('the rail fills to the current node, and to nothing beyond', (
    tester,
  ) async {
    await _open(tester);
    // Rows 0 to 2 are done: their stretch is full. Row 3 is current: the
    // fill ends 28 past its node's centre. Rows 4 to 6 have none.
    for (var i = 0; i < 3; i++) {
      expect(_fill(tester, i), greaterThan(0), reason: 'row $i');
      expect(
        _fill(tester, i),
        tester.getSize(find.byKey(ChaptersPage.railTrackKey(i))).height,
      );
    }
    for (var i = 4; i < 7; i++) {
      expect(_fill(tester, i), 0, reason: 'row $i');
    }
    final row = tester.getSize(
      find.byKey(ChaptersPage.rowKey(ChapterId.ch4Salon)),
    );
    expect(_fill(tester, 3), row.height / 2 + 28);
  });

  testWidgets('the rail animates once per chapter change', (tester) async {
    final container = await _open(tester, location: '/apartment');
    final router = container.read(routerProvider);
    // The first entry: still growing a moment in.
    router.go('/apartment/chapters');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final early = _fill(tester, 3);
    await tester.pumpAndSettle();
    final settled = _fill(tester, 3);
    expect(early, lessThan(settled));

    // Away and back, the chapter unchanged: drawn full at once.
    router.go('/apartment');
    await tester.pumpAndSettle();
    router.go('/apartment/chapters');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(_fill(tester, 3), settled);
  });

  testWidgets('at the end of the story the rail is full and nothing is '
      'current', (tester) async {
    final content = artboardSalonContent();
    await _open(
      tester,
      owned: {
        microOld,
        shabka,
        for (final item in content.itemsOf(RoomId.salon))
          (SkuKind.item, item.itemId),
        (SkuKind.chapter, 'ch5_kitchen'),
        (SkuKind.chapter, 'ch6_bedroom'),
        (SkuKind.chapter, 'ch7_wedding'),
      },
    );
    expect(find.text(_l10n.chaptersCurrent(_numbers.integer(4))), findsNothing);
    for (var i = 0; i < 7; i++) {
      expect(_fill(tester, i), greaterThan(0), reason: 'row $i');
    }
  });

  testWidgets('seven rows scroll at 1.3x on a short phone', (tester) async {
    final semantics = tester.ensureSemantics();
    await _open(tester, textScale: 1.3, size: const Size(360, 640));
    await tester.scrollUntilVisible(
      find.byKey(ChaptersPage.rowKey(ChapterId.ch7Wedding)),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.byKey(ChaptersPage.rowKey(ChapterId.ch7Wedding)),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
}
