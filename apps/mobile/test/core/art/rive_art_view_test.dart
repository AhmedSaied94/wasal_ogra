import 'dart:io' as io;

import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rive/rive.dart' as rive;
import 'package:wassal/core/art/rive_art.dart';
import 'package:wassal/core/art/rive_scenes.dart';
import 'package:wassal/core/theme/components/story.dart';
import 'package:wassal/core/theme/components/vehicle_sprite.dart';
import 'package:wassal/core/theme/components/characters.dart';

// The art outside the trip's seats in Rive, each with its static art as the
// fallback (tasks.md T108, contracts/rive-characters.md "How the app uses
// it"): without the file, with a file that lacks the artboard, and under
// reduced motion, the fallback draws; with the file, Rive does.

const _fallback = ValueKey('fallback');

/// One of each, by what draws it with the file.
List<Widget> _all() => [
  const MicrobusLoader(label: 'x'),
  const CharacterAvatar('belya'),
  const CoachHand(),
  const VehicleSprite(
    vehicle: VehicleId.microOld,
    fallback: SizedBox(key: _fallback),
  ),
];

Future<void> _pump(
  WidgetTester tester, {
  RiveArt? art,
  bool scoped = true,
  bool reduced = false,
}) async {
  final children = Column(
    children: [
      for (final w in _all()) SizedBox(width: 236, height: 150, child: w),
    ],
  );
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(disableAnimations: reduced),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: scoped ? RiveArtScope(art: art, child: children) : children,
      ),
    ),
  );
}

void _expectFallbacks() {
  expect(find.byType(rive.RiveWidget), findsNothing);
  expect(find.byKey(MicrobusLoader.markerKey), findsOneWidget);
  expect(find.byKey(_fallback), findsOneWidget);
  expect(
    find.descendant(
      of: find.byType(CharacterAvatar),
      matching: find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == 'SvgPicture',
      ),
    ),
    findsOneWidget,
  );
  expect(
    find.descendant(
      of: find.byType(CoachHand),
      matching: find.byType(CustomPaint),
    ),
    findsWidgets,
  );
}

void main() {
  testWidgets('without the scope: the static art', (tester) async {
    await _pump(tester, scoped: false);
    _expectFallbacks();
  });

  testWidgets('without the file: the static art', (tester) async {
    await _pump(tester, art: const RiveArt.none(['missing']));
    _expectFallbacks();
  });

  test("the six story characters' looks", () {
    expect(CharacterAvatar.looks, {
      'usta': 18,
      'salma': 19,
      'bride_father': 20,
      'bride_mother': 21,
      'moallem': 22,
      'belya': 23,
    });
  });

  test('each vehicle has its look', () {
    expect(
      [for (final v in VehicleId.values) VehicleSprite.look(v)],
      [0, 1, 2, 3],
    );
  });

  group('with the file', () {
    late rive.File file;
    late RiveArt art;

    Future<void> load(WidgetTester tester) async {
      await tester.runAsync(() async {
        await rive.RiveNative.init();
        final bytes = io.File(riveArtAsset).readAsBytesSync();
        file = (await rive.File.decode(
          bytes,
          riveFactory: rive.Factory.flutter,
        ))!;
      });
      art = checkRiveArt(file);
      addTearDown(file.dispose);
    }

    testWidgets('each draws Rive', (tester) async {
      await load(tester);
      await _pump(tester, art: art);
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byType(rive.RiveWidget), findsNWidgets(4));
      await tester.pumpWidget(const SizedBox());
    }, tags: ['rive']);

    testWidgets('its view model is bound, and set on every build', (
      tester,
    ) async {
      await load(tester);
      final looks = <double?>[];
      Future<void> pump(double look) => tester.pumpWidget(
        RiveArtScope(
          art: art,
          child: RiveArtView(
            artboard: 'Vehicle',
            fallback: const SizedBox(key: _fallback),
            bind: (model) {
              model.number('look')?.value = look;
              looks.add(model.number('look')?.value);
            },
          ),
        ),
      );
      await pump(1);
      await pump(2);
      expect(looks, [1, 2]);
      expect(find.byType(rive.RiveWidget), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    }, tags: ['rive']);

    testWidgets('under reduced motion, the static art', (tester) async {
      await load(tester);
      await _pump(tester, art: art, reduced: true);
      _expectFallbacks();
      await tester.pumpWidget(const SizedBox());
    }, tags: ['rive']);

    testWidgets('an artboard that failed its check: its static art alone', (
      tester,
    ) async {
      await load(tester);
      final partial = RiveArt(
        file: file,
        usable: art.usable.difference({'LoadingWheel'}),
        problems: const ['artboard LoadingWheel: missing'],
      );
      await _pump(tester, art: partial);
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byKey(MicrobusLoader.markerKey), findsOneWidget);
      expect(find.byType(rive.RiveWidget), findsNWidgets(3));
      await tester.pumpWidget(const SizedBox());
    }, tags: ['rive']);
  });

  // The scope's second file (specs/012.5-m22-animated-scenes,
  // contracts/rive-scenes.md "Drawing"): a view reads the file its source
  // names, and draws its fallback without it.
  group('the scenes file', () {
    const panel = RiveArtView(
      source: RiveArtSource.scenes,
      artboard: 'opening_key',
      fit: rive.Fit.cover,
      alignment: Alignment.bottomCenter,
      fallback: SizedBox(key: _fallback),
    );

    testWidgets('a scenes view without the scenes file: its fallback', (
      tester,
    ) async {
      await tester.pumpWidget(
        const RiveArtScope(art: RiveArt.none(), child: panel),
      );
      expect(find.byKey(_fallback), findsOneWidget);
      expect(find.byType(rive.RiveWidget), findsNothing);
    });

    group('with it', () {
      late rive.File file;
      late RiveArt scenes;

      Future<void> load(WidgetTester tester) async {
        await tester.runAsync(() async {
          await rive.RiveNative.init();
          final bytes = io.File(riveScenesAsset).readAsBytesSync();
          file = (await rive.File.decode(
            bytes,
            riveFactory: rive.Factory.flutter,
          ))!;
        });
        scenes = checkRiveArt(file, sceneContract);
        addTearDown(file.dispose);
      }

      testWidgets('a scenes view draws Rive, with the fit and alignment it '
          'asks for', (tester) async {
        await load(tester);
        await tester.pumpWidget(
          RiveArtScope(art: null, scenes: scenes, child: panel),
        );
        await tester.pump(const Duration(milliseconds: 16));
        final widget = tester.widget<rive.RiveWidget>(
          find.byType(rive.RiveWidget),
        );
        expect(widget.fit, rive.Fit.cover);
        expect(widget.alignment, Alignment.bottomCenter);
        await tester.pumpWidget(const SizedBox());
      }, tags: ['rive']);

      testWidgets('a characters view never reads the scenes file', (
        tester,
      ) async {
        await load(tester);
        await tester.pumpWidget(
          RiveArtScope(
            art: const RiveArt.none(),
            scenes: scenes,
            child: const RiveArtView(
              artboard: 'opening_key',
              fallback: SizedBox(key: _fallback),
            ),
          ),
        );
        expect(find.byKey(_fallback), findsOneWidget);
        expect(find.byType(rive.RiveWidget), findsNothing);
      }, tags: ['rive']);

      testWidgets('a change of source closes the view', (tester) async {
        await load(tester);
        Future<void> pump(RiveArtSource source) => tester.pumpWidget(
          RiveArtScope(
            art: const RiveArt.none(),
            scenes: scenes,
            child: RiveArtView(
              source: source,
              artboard: 'opening_key',
              fallback: const SizedBox(key: _fallback),
            ),
          ),
        );
        await pump(RiveArtSource.scenes);
        expect(find.byType(rive.RiveWidget), findsOneWidget);
        await pump(RiveArtSource.characters);
        expect(find.byType(rive.RiveWidget), findsNothing);
        expect(find.byKey(_fallback), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      }, tags: ['rive']);

      testWidgets('a file whose contract lacks the artboard: its fallback, '
          'never a throw', (tester) async {
        await load(tester);
        // Built by hand, with no contract: the characters' is read.
        final bare = RiveArt(
          file: file,
          usable: const {'opening_key'},
          problems: const [],
        );
        await tester.pumpWidget(
          RiveArtScope(art: null, scenes: bare, child: panel),
        );
        expect(tester.takeException(), isNull);
        expect(find.byKey(_fallback), findsOneWidget);
        expect(find.byType(rive.RiveWidget), findsNothing);
      }, tags: ['rive']);
    });
  });
}
