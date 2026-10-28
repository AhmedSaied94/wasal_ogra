import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/art/panel_art.dart';
import 'package:wassal/core/theme/components/characters.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';

import '../../helpers/design_component.dart';

// A comic panel's art (specs/012-m07-onboarding/contracts/scenes.md "Panel
// art"): a drawing by slug, or the fallback drawn from the speakers.

Future<void> _pump(WidgetTester tester, Widget art) =>
    pumpDesignComponent(tester, SizedBox(width: 358, height: 540, child: art));

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
}
