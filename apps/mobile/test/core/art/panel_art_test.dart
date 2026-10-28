import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rive/rive.dart' as rive;
import 'package:wassal/core/art/panel_art.dart';
import 'package:wassal/core/art/rive_art.dart';
import 'package:wassal/core/art/rive_scenes.dart';
import 'package:wassal/core/theme/components/characters.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';

import '../../helpers/design_component.dart';

// A comic panel's art (specs/012-m07-onboarding/contracts/scenes.md "Panel
// art"): a drawing by slug, or the fallback drawn from the speakers.

Future<void> _pump(
  WidgetTester tester,
  Widget art, {
  RiveArt? scenes,
  bool reducedMotion = false,
}) => pumpDesignComponent(
  tester,
  RiveArtScope(
    art: null,
    scenes: scenes,
    child: SizedBox(width: 358, height: 540, child: art),
  ),
  reducedMotion: reducedMotion,
);

/// Whether [slug], animated over [scenes], draws its drawing and no Rive.
Future<void> _expectDrawing(
  WidgetTester tester,
  String slug, {
  RiveArt? scenes,
  bool reducedMotion = false,
}) async {
  await _pump(
    tester,
    PanelArt(slug: slug, speakers: const [], animate: true),
    scenes: scenes,
    reducedMotion: reducedMotion,
  );
  expect(find.byType(SvgPicture), findsOneWidget, reason: slug);
  expect(find.byType(rive.RiveWidget), findsNothing, reason: slug);
}

void main() {
  test("the sample's six panels map to their assets; other slugs to none", () {
    for (final slug in const [
      'opening_key',
      'opening_stand',
      'opening_go',
      'stand_morning',
      'salma_waiting',
      'usta_decides',
    ]) {
      expect(
        PanelArt.assetFor(slug),
        'assets/illustrations/panels/$slug.svg',
        reason: slug,
      );
    }
    expect(PanelArt.assetFor('no_such_panel'), isNull);
    expect(PanelArt.assetFor(''), isNull);
  });

  testWidgets('a drawn slug shows its drawing', (tester) async {
    await _pump(
      tester,
      const PanelArt(slug: 'opening_key', speakers: ['moallem']),
    );
    expect(find.byType(SvgPicture), findsOneWidget);
    expect(find.byType(PanelFallback), findsNothing);
  });

  testWidgets('an unknown slug draws the fallback from the speakers', (
    tester,
  ) async {
    await _pump(
      tester,
      const PanelArt(
        slug: 'no_such_panel',
        speakers: ['narrator', 'moallem', 'usta'],
        current: 'usta',
      ),
    );
    final fallback = tester.widget<PanelFallback>(find.byType(PanelFallback));
    expect(fallback.speakers, ['moallem', 'usta']);
    expect(fallback.current, 'usta');
  });

  testWidgets('the fallback: sky, a street, every speaker but the narrator '
      'at 1.6×, the current one in front', (tester) async {
    await _pump(
      tester,
      const PanelFallback(
        speakers: ['narrator', 'moallem', 'belya'],
        current: 'moallem',
      ),
    );
    final avatars = tester
        .widgetList<CharacterAvatar>(find.byType(CharacterAvatar))
        .map((a) => a.character)
        .toList();
    // Painted in order: the current speaker last, so in front.
    expect(avatars, ['belya', 'moallem']);
    for (final character in avatars) {
      final size = tester.getSize(
        find.byKey(PanelFallback.avatarKey(character)),
      );
      expect(size.width, closeTo(CharacterAvatar.size.width * 1.6, 0.01));
      expect(size.height, closeTo(CharacterAvatar.size.height * 1.6, 0.01));
    }
    final sky = tester.widget<ColoredBox>(find.byKey(PanelFallback.skyKey));
    expect(sky.color, ColorTokens.sceneSky);
    expect(find.byKey(PanelFallback.streetKey), findsOneWidget);
    expect(
      tester.getRect(find.byKey(PanelFallback.streetKey)).bottom,
      tester.getRect(find.byType(PanelFallback)).bottom,
    );
  });

  testWidgets('a panel with only the narrator draws the street alone', (
    tester,
  ) async {
    await _pump(tester, const PanelFallback(speakers: ['narrator']));
    expect(find.byType(CharacterAvatar), findsNothing);
    expect(find.byKey(PanelFallback.streetKey), findsOneWidget);
  });

  // The animation (specs/012.5-m22-animated-scenes, contracts/rive-scenes.md
  // "Panel art").
  group('animated', () {
    testWidgets('without a scope: the drawing', (tester) async {
      await _pump(
        tester,
        const PanelArt(slug: 'opening_key', speakers: [], animate: true),
      );
      expect(find.byType(SvgPicture), findsOneWidget);
      expect(find.byType(rive.RiveWidget), findsNothing);
    });

    testWidgets("the scenes' artboard, filling the panel from the bottom, "
        'over its drawing', (tester) async {
      await _pump(
        tester,
        const PanelArt(slug: 'opening_stand', speakers: [], animate: true),
      );
      final view = tester.widget<RiveArtView>(find.byType(RiveArtView));
      expect(view.source, RiveArtSource.scenes);
      expect(view.artboard, 'opening_stand');
      expect(view.fit, rive.Fit.cover);
      expect(view.alignment, Alignment.bottomCenter);
      expect(view.fallback, isA<SvgPicture>());
    });

    testWidgets('not animated: M07\'s art, no Rive view', (tester) async {
      await _pump(
        tester,
        const PanelArt(slug: 'opening_stand', speakers: ['moallem']),
      );
      expect(find.byType(RiveArtView), findsNothing);
      expect(find.byType(SvgPicture), findsOneWidget);
    });

    test('bindTalkers sets all four Booleans', () {
      final model = _FakeModel();
      PanelArt.bindTalkers('usta')(model);
      expect(model.values, {
        'moallem': false,
        'usta': true,
        'belya': false,
        'salma': false,
      });
      PanelArt.bindTalkers(null)(model);
      expect(model.values.values, everyElement(isFalse));
      expect(model.values.keys, unorderedEquals(sceneTalkers));
    });
  });

  // The release draft's names for the سلمى scene (data-model.md "Art slug").
  group('aliases', () {
    const aliases = {
      'ch1_stand_morning': 'stand_morning',
      'ch1_salma_asks': 'salma_waiting',
      'ch1_usta_dreams': 'usta_decides',
    };

    test('artFor maps the three ch1_ slugs; any other to itself', () {
      for (final MapEntry(key: alias, value: art) in aliases.entries) {
        expect(PanelArt.artFor(alias), art, reason: alias);
        expect(PanelArt.assetFor(alias), PanelArt.assetFor(art), reason: alias);
        expect(PanelArt.assetFor(alias), isNotNull, reason: alias);
      }
      for (final slug in [...scenePanelSlugs, 'ch1_moallem_counts', 'x']) {
        expect(PanelArt.artFor(slug), slug);
      }
    });

    testWidgets('an animated alias opens its canonical artboard', (
      tester,
    ) async {
      for (final MapEntry(key: alias, value: art) in aliases.entries) {
        await _pump(
          tester,
          PanelArt(slug: alias, speakers: const [], animate: true),
        );
        final view = tester.widget<RiveArtView>(find.byType(RiveArtView));
        expect(view.artboard, art, reason: alias);
        expect(view.fallback, isA<SvgPicture>(), reason: alias);
      }
    });
  });

  // The fallback order (spec FR-006): the artboard, else the drawing, else
  // PanelFallback.
  group('falls back', () {
    testWidgets('without the scenes file: every panel its drawing', (
      tester,
    ) async {
      for (final slug in scenePanelSlugs) {
        await _expectDrawing(
          tester,
          slug,
          scenes: const RiveArt.none(['assets/rive/wassal_scenes.riv: gone']),
        );
      }
    });

    testWidgets('a slug with neither an artboard nor a drawing: '
        'PanelFallback', (tester) async {
      await _pump(
        tester,
        const PanelArt(
          slug: 'ch1_moallem_counts',
          speakers: ['moallem'],
          animate: true,
        ),
        scenes: const RiveArt.none(),
      );
      expect(find.byType(PanelFallback), findsOneWidget);
      expect(find.byType(rive.RiveWidget), findsNothing);
    });
  });
}

/// A panel's view model, holding what was set.
final class _FakeModel implements rive.ViewModelInstance {
  final values = <String, bool>{};

  @override
  rive.ViewModelInstanceBoolean? boolean(String path) => _FakeBool(this, path);

  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeBool implements rive.ViewModelInstanceBoolean {
  _FakeBool(this.model, this.path);

  final _FakeModel model;
  final String path;

  @override
  bool get value => model.values[path] ?? false;

  @override
  set value(bool value) => model.values[path] = value;

  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
