import 'dart:convert';

import 'package:content_models/content_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show Size;
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/features/story/presentation/scene_viewer_page.dart';

import '../../helpers/lines.dart';
import '../../helpers/progress.dart';
import '../../helpers/surfaces.dart';
import '../../helpers/synthetic_packs.dart';
import '../design_check.dart';

// `SceneViewer` as the board draws it (specs/015-m10-apartment-story, T094):
// the family's visit, chapter 4's goal scene, on its fourth and last panel,
// the bride's mother asking after the crystal chandelier and الأسطى
// answering.

/// The sample scene's id: the artboard's, in chapter 4.
const sceneViewerSceneId = 'family_visit';

/// The artboard's scene in place of chapter 4's goal scene.
Map<String, Object?> sceneViewerPack() {
  final json = jsonDecode(jsonEncode(artboardSalon())) as Map<String, Object?>;
  Map<String, Object?> line(String speaker, String text) => {
    'speaker': speaker,
    'text': {'ar-EG': text},
  };
  Map<String, Object?> panel(String art, List<Map<String, Object?>> lines) => {
    'art': art,
    'lines': lines,
  };
  for (final chapter in json['chapters']! as List<Object?>) {
    final map = chapter! as Map<String, Object?>;
    if (map['chapter_id'] != 'ch4_salon') continue;
    map['scenes'] = [
      {
        'scene_id': sceneViewerSceneId,
        'title': {'ar-EG': 'زيارة أهل العروسة'},
        'panels': [
          panel('ch4_mother_looks', [line('narrator', 'أهل العروسة وصلوا')]),
          panel('ch4_mother_looks', [line('bride_mother', 'الصالة حلوة')]),
          panel('salma_waiting', [line('salma', 'أنا كنت عارفة')]),
          panel('ch4_mother_looks', [
            line('bride_mother', 'والنجفة كريستال إن شاء الله؟'),
            line('usta', 'إن شاء الله يا حاجة.. المشوار الجاي.'),
          ]),
        ],
      },
    ];
  }
  return json;
}

/// The viewer on the last panel of the sample scene, chapter 4 complete.
Future<ProviderContainer> pumpSceneViewer(
  WidgetTester tester, {
  DigitStyle digits = DigitStyle.arabicIndic,
  Size? size,
  double textScale = 1.0,
  bool onLastPanel = true,
}) async {
  final all = [
    for (final item in artboardSalonContent().itemsOf(RoomId.salon))
      item.itemId,
  ];
  final (container, _) = await pumpLinesApp(
    tester,
    pack: sceneViewerPack(),
    digits: digits,
    textScale: textScale,
    location: '/story/scene/$sceneViewerSceneId',
    settle: false,
    // No name given: الأسطى says «الأسطى», as the board has him.
    state: (nowMs) => playerState(
      stars: hayDone,
      owned: {microOld, shabka, for (final id in all) (SkuKind.item, id)},
      styles: const {
        'salon.nish': 'classic',
        'salon.sitara': 'plain',
        'salon.antreeh': 'classic',
      },
    )(nowMs).copyWith(displayName: () => null),
  );
  if (size == null) {
    applyDesignSurface(tester, const Size(390, 844), topInset: designTopInset);
  } else {
    applySurfaceSize(tester, size);
  }
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  if (onLastPanel) {
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(SceneViewerPage.panelKey));
      await tester.pumpAndSettle();
    }
  }
  return container;
}
