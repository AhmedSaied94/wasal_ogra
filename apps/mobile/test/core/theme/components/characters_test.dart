import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/components/characters.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';

import '../../../helpers/design_component.dart';

// The story's characters and their lines (HANDOFF §3.4 `SpeechBubble`,
// `CharacterAvatar`), shared by the trip and the first session
// (specs/012-m07-onboarding plan "Structure decision"). The bubbles' place
// in the scene is tested with the trip; `CharacterAvatar`'s art with Rive's
// (test/core/art/rive_art_view_test.dart).

/// Every fill drawn under [finder].
Set<Color?> _fills(WidgetTester tester, Finder finder) => {
  for (final box in tester.widgetList<DecoratedBox>(
    find.descendant(of: finder, matching: find.byType(DecoratedBox)),
  ))
    if (box.decoration case BoxDecoration(:final color)) color,
};

void main() {
  group('SpeechBubble', () {
    for (final (variant, bg) in [
      (SpeechBubbleVariant.normal, ColorTokens.paper),
      (SpeechBubbleVariant.warn, ColorTokens.dangerSoft),
      (SpeechBubbleVariant.fight, ColorTokens.danger),
      (SpeechBubbleVariant.thanks, ColorTokens.primarySoft),
      (SpeechBubbleVariant.character, ColorTokens.paper),
    ]) {
      testWidgets('${variant.name}: its fill, 16 pt text never scaled', (
        tester,
      ) async {
        await pumpDesignComponent(
          tester,
          SpeechBubble(
            text: 'الباقي يا أسطى!',
            variant: variant,
            name: variant == SpeechBubbleVariant.character ? 'بلية' : null,
          ),
          textScale: 1.3,
        );
        final bubble = find.byType(SpeechBubble);
        expect(_fills(tester, bubble), contains(bg));
        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(of: bubble, matching: find.byType(RichText)).last,
        );
        expect(paragraph.textScaler.scale(16), 16);
        expect(
          find.descendant(of: bubble, matching: find.text('بلية')),
          variant == SpeechBubbleVariant.character
              ? findsOneWidget
              : findsNothing,
        );
      });
    }

    testWidgets('without its tail, only the body', (tester) async {
      await pumpDesignComponent(
        tester,
        const SpeechBubble(text: 'هه؟', tail: false),
      );
      expect(find.byType(SpeechBubbleTail), findsNothing);
    });

    testWidgets('pops in, and just appears under reduced motion', (
      tester,
    ) async {
      await pumpDesignComponent(tester, const SpeechBubble(text: 'هه؟'));
      expect(find.byType(TweenAnimationBuilder<double>), findsOneWidget);
      await pumpDesignComponent(
        tester,
        const SpeechBubble(text: 'هه؟'),
        reducedMotion: true,
      );
      expect(find.byType(TweenAnimationBuilder<double>), findsNothing);
    });
  });

  group('CharacterAvatar', () {
    testWidgets('is the head-and-shoulders crop, 96×110', (tester) async {
      await pumpDesignComponent(tester, const CharacterAvatar('usta'));
      expect(tester.getSize(find.byType(CharacterAvatar)), const Size(96, 110));
    });
  });
}
