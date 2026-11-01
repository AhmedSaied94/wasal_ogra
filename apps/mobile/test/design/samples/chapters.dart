import 'dart:convert';

import 'package:content_models/content_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show Size;
import 'package:wassal/core/l10n/digit_style.dart';

import '../../helpers/lines.dart';
import '../../helpers/progress.dart';
import '../../helpers/surfaces.dart';
import '../../helpers/synthetic_packs.dart';
import '../design_check.dart';

// `Chapters` and `Album` as the boards draw them (specs/015-m10-apartment-
// story, T109): the salon with two pieces installed, chapters 1 to 3 done and
// 4 current, and one scene per chapter titled as the boards have them. The
// album's cards follow the pack's scenes (research R18), so these seven are
// what makes its count «٣ من ٧».

/// The seven chapters' one scene each: title and the art of its panels.
const _scenes = <String, (String, List<String>)>{
  'ch1_first_job': (
    'سلمى في الموقف',
    ['stand_morning', 'salma_waiting', 'usta_decides'],
  ),
  'ch2_her_father': (
    '«بتشتغل إيه؟»',
    ['ch4_mother_looks', 'opening_key', 'usta_decides'],
  ),
  'ch3_shabka': (
    'قراءة الفاتحة',
    ['ch4_mother_looks', 'ch4_mother_looks', 'salma_waiting'],
  ),
  'ch4_salon': (
    'زيارة أهل العروسة',
    ['ch4_mother_looks', 'ch4_mother_looks', 'salma_waiting'],
  ),
  'ch5_kitchen': (
    'أول عزومة',
    ['stand_morning', 'salma_waiting', 'usta_decides'],
  ),
  'ch6_bedroom': (
    'كتب الكتاب',
    ['stand_morning', 'salma_waiting', 'usta_decides'],
  ),
  'ch7_wedding': ('الفرح', ['stand_morning', 'salma_waiting', 'usta_decides']),
};

/// [artboardSalon]'s seven chapters, each with its goal scene (no `plays`:
/// it unlocks when the chapter is complete).
Map<String, Object?> chaptersPack() {
  final json = jsonDecode(jsonEncode(artboardSalon())) as Map<String, Object?>;
  for (final chapter in json['chapters']! as List<Object?>) {
    final map = chapter! as Map<String, Object?>;
    final (title, arts) = _scenes[map['chapter_id']]!;
    map['scenes'] = [
      {
        'scene_id': '${map['chapter_id']}_scene',
        'title': {'ar-EG': title},
        'panels': [
          for (final art in arts)
            {
              'art': art,
              'lines': [
                {
                  'speaker': 'narrator',
                  'text': {'ar-EG': title},
                },
              ],
            },
        ],
      },
    ];
  }
  return json;
}

Future<ProviderContainer> _pump(
  WidgetTester tester,
  String location, {
  required DigitStyle digits,
  required Size? size,
  required double textScale,
}) async {
  final (container, _) = await pumpLinesApp(
    tester,
    pack: chaptersPack(),
    digits: digits,
    textScale: textScale,
    location: location,
    settle: false,
    state: playerState(
      stars: hayDone,
      owned: {
        microOld,
        shabka,
        (SkuKind.item, 'salon.nish'),
        (SkuKind.item, 'salon.sitara'),
      },
      styles: const {'salon.nish': 'crystal', 'salon.sitara': 'plain'},
    ),
  );
  if (size == null) {
    applyDesignSurface(tester, const Size(390, 844), topInset: designTopInset);
  } else {
    applySurfaceSize(tester, size);
  }
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  return container;
}

Future<ProviderContainer> pumpChapters(
  WidgetTester tester, {
  DigitStyle digits = DigitStyle.arabicIndic,
  Size? size,
  double textScale = 1.0,
}) => _pump(
  tester,
  '/apartment/chapters',
  digits: digits,
  size: size,
  textScale: textScale,
);

Future<ProviderContainer> pumpAlbum(
  WidgetTester tester, {
  DigitStyle digits = DigitStyle.arabicIndic,
  Size? size,
  double textScale = 1.0,
}) => _pump(
  tester,
  '/story/album',
  digits: digits,
  size: size,
  textScale: textScale,
);
