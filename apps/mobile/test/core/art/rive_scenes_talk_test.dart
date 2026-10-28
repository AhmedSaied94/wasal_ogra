// Who talks where in the scenes' file (specs/012.5-m22-animated-scenes,
// research R11, contracts/ci-checks.md "Rive tests"): each panel rendered at
// fixed times with each Boolean on and off. A Boolean changes the pixels
// only where its character is drawn, and every spoken line's speaker is
// drawn in its panel. Needs Rive's Linux library.
@Tags(['rive'])
library;

import 'dart:io' as io;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rive/rive.dart' as rive;
import 'package:wassal/core/art/panel_art.dart';
import 'package:wassal/core/art/rive_scenes.dart';
import 'package:wassal/features/onboarding/domain/first_session.dart';

import '../../helpers/economy.dart';
import '../../helpers/tutorial_content.dart';

/// Within the first loop, when each character's mouth is open at least once
/// with its Boolean on.
const _times = [0.2, 0.35, 0.65, 1.15, 1.3];
const _frame = 1 / 60;

/// One loop of the panels' `scene` animation.
const _loopS = 4.8;

/// The spec's "Who talks where": the characters each panel draws.
const _drawn = {
  'opening_key': {'moallem', 'usta'},
  'opening_stand': {'moallem', 'usta'},
  'opening_go': {'moallem', 'belya'},
  'stand_morning': {'usta'},
  'salma_waiting': {'usta', 'salma'},
  'usta_decides': {'usta'},
};

late rive.File _file;

/// [panel] at [times] (seconds from its start) with [talker]'s Boolean on,
/// or none, as raw RGBA.
Future<List<Uint8List>> _frames(
  String panel,
  String? talker,
  List<double> times,
) async {
  final artboard = _file.artboard(panel)!;
  final machine = artboard.stateMachine(scenePanelMachine)!;
  final model = _file.defaultArtboardViewModel(artboard)!;
  final instance = model.createDefaultInstance()!;
  model.dispose();
  machine.bindViewModelInstance(instance);
  if (talker != null) instance.boolean(talker)!.value = true;
  machine.advanceAndApply(0);
  final out = <Uint8List>[];
  var t = 0.0;
  for (final target in times) {
    while (t < target - 1e-6) {
      machine.advanceAndApply(_frame);
      t += _frame;
    }
    final recorder = ui.PictureRecorder();
    final renderer = rive.Renderer.make(Canvas(recorder));
    renderer.align(
      rive.Fit.fill,
      Alignment.topLeft,
      rive.AABB.fromValues(0, 0, scenePanelSize.width, scenePanelSize.height),
      artboard.bounds,
      1,
    );
    artboard.draw(renderer);
    renderer.dispose();
    final image = await recorder.endRecording().toImage(
      scenePanelSize.width.toInt(),
      scenePanelSize.height.toInt(),
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    out.add(bytes!.buffer.asUint8List());
  }
  instance.dispose();
  machine.dispose();
  artboard.dispose();
  return out;
}

/// How many pixels differ.
int _diff(Uint8List a, Uint8List b) {
  var n = 0;
  for (var i = 0; i < a.length; i += 4) {
    if (a[i] != b[i] || a[i + 1] != b[i + 1] || a[i + 2] != b[i + 2]) n++;
  }
  return n;
}

Map<String, Map<String, bool>>? _table;

/// Whether each Boolean changes each panel at one of [_times].
Future<Map<String, Map<String, bool>>> _talks(WidgetTester tester) async =>
    _table ??= (await tester.runAsync(() async {
      final table = <String, Map<String, bool>>{};
      for (final panel in scenePanelSlugs) {
        final still = await _frames(panel, null, _times);
        table[panel] = {
          for (final talker in sceneTalkers)
            talker: await _frames(panel, talker, _times).then(
              (on) => [
                for (var i = 0; i < _times.length; i++) _diff(still[i], on[i]),
              ].any((n) => n > 0),
            ),
        };
      }
      return table;
    }))!;

/// Each spoken line's speaker and the panel its art draws.
Iterable<(String panel, String speaker)> _spoken(Scene scene) sync* {
  for (final panel in scene.panels) {
    for (final line in panel.lines) {
      if (line.speaker != PanelFallback.narrator) {
        yield (PanelArt.artFor(panel.art), line.speaker);
      }
    }
  }
}

void main() {
  setUpAll(() async {
    await rive.RiveNative.init();
    final bytes = io.File(riveScenesAsset).readAsBytesSync();
    _file = (await rive.File.decode(bytes, riveFactory: rive.Factory.flutter))!;
  });

  tearDownAll(() => _file.dispose());

  testWidgets('a Boolean changes a panel only where its character is drawn', (
    tester,
  ) async {
    final talks = await _talks(tester);
    for (final panel in scenePanelSlugs) {
      for (final talker in sceneTalkers) {
        expect(
          talks[panel]![talker],
          _drawn[panel]!.contains(talker),
          reason: '$talker in $panel',
        );
      }
    }
  });

  testWidgets("every spoken line of the sample's opening and the_stand: its "
      'speaker talks in its panel', (tester) async {
    final talks = await _talks(tester);
    final sample = sampleContent();
    final lines = [
      for (final id in ['opening', 'the_stand'])
        ..._spoken(sceneOf(sample, id)!),
    ];
    expect(lines, hasLength(8));
    for (final (panel, speaker) in lines) {
      expect(talks[panel]![speaker], isTrue, reason: '$speaker in $panel');
    }
  });

  testWidgets("every spoken line of the draft's first_sight: its speaker "
      'talks in its panel, through artFor', (tester) async {
    final talks = await _talks(tester);
    final lines = [..._spoken(draftFirstSight())];
    expect(lines, hasLength(5));
    for (final (panel, speaker) in lines) {
      expect(talks[panel]?[speaker], isTrue, reason: '$speaker in $panel');
    }
  });

  testWidgets('two runs give the same pixels', (tester) async {
    await tester.runAsync(() async {
      for (final panel in scenePanelSlugs) {
        final a = await _frames(panel, 'usta', _times);
        final b = await _frames(panel, 'usta', _times);
        for (var i = 0; i < _times.length; i++) {
          expect(_diff(a[i], b[i]), 0, reason: '$panel at ${_times[i]} s');
        }
      }
    });
  });

  testWidgets('the loop closes: 4.8 s on, under 1% of the pixels differ', (
    tester,
  ) async {
    const pixels = 358 * 540;
    await tester.runAsync(() async {
      for (final panel in scenePanelSlugs) {
        final [first, later] = await _frames(panel, null, [
          _times.first,
          _times.first + _loopS,
        ]);
        expect(_diff(first, later), lessThan(pixels ~/ 100), reason: panel);
      }
    });
  });
}
