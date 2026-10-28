// The story's characters and what they say (HANDOFF §3.4 `SpeechBubble` and
// `CharacterAvatar`). The trip and the first session's screens both draw
// them (specs/012-m07-onboarding plan "Structure decision"), so they live
// with the shared components.
//
// - `SpeechBubble`: a passenger's or a character's line, its tail under its
//   middle unless the scene places it; it pops from its tail, and just
//   appears under reduced motion.
// - `CharacterAvatar`: `wassal.riv`'s `Person` with the character's look,
//   cropped to the head and shoulders as `Tutorial` block 6 draws بلية; its
//   static art from `assets/illustrations/characters/` without the file and
//   under reduced motion.
import 'dart:math';

import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rive/rive.dart' as rive;
import 'package:wassal/core/art/rive_art.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';

enum SpeechBubbleVariant { normal, warn, fight, thanks, character }

typedef _BubbleColors = ({Color bg, Color text, BoxShadow lip});

_BubbleColors _colorsOf(SpeechBubbleVariant variant) => switch (variant) {
  SpeechBubbleVariant.normal || SpeechBubbleVariant.character => (
    bg: ColorTokens.paper,
    text: ColorTokens.ink,
    lip: LipTokens.bubble,
  ),
  SpeechBubbleVariant.warn => (
    bg: ColorTokens.dangerSoft,
    text: ColorTokens.ink,
    lip: LipTokens.bubbleWarn,
  ),
  SpeechBubbleVariant.fight => (
    bg: ColorTokens.danger,
    text: ColorTokens.ink,
    lip: DesignExtras.bubbleFightLip,
  ),
  SpeechBubbleVariant.thanks => (
    bg: ColorTokens.primarySoft,
    text: ColorTokens.primary,
    lip: LipTokens.bubble,
  ),
};

/// The tail: a 14 pt square turned 45°, poking 6 pt below the body.
const bubbleTailHalfDiagonal = DesignExtras.bubbleTail * 0.7071067811865476;

/// How far the body's bottom sits above the tail square's centre.
const bubbleTailInset = DesignExtras.bubbleTail / 2 - 6;

/// A speech bubble; on its own it draws its tail under its middle.
class SpeechBubble extends StatelessWidget {
  const SpeechBubble({
    required this.text,
    this.variant = SpeechBubbleVariant.normal,
    this.name,
    this.tail = true,
    this.padding,
    this.quoteStyle,
    this.scaled = false,
    this.fill,
    super.key,
  });

  final String text;
  final SpeechBubbleVariant variant;

  /// The body's colour instead of the variant's: `ground` on a white card
  /// (the fuel lesson).
  final Color? fill;

  /// The speaker's name over a character's line.
  final String? name;

  /// A character bubble's own padding and line style (بلية's hint).
  final EdgeInsets? padding;
  final TextStyle? quoteStyle;

  /// Whether its text follows the system's scale up to 1.3 (the hint, as
  /// cards do); passengers' bubbles never scale.
  final bool scaled;

  /// Whether to draw the tail; the scene places it at the speaker.
  final bool tail;

  static Key tailKey(String passengerId) =>
      ValueKey('bubble-tail-$passengerId');

  @override
  Widget build(BuildContext context) {
    final colors = _colorsOf(variant);
    final character = variant == SpeechBubbleVariant.character;
    final scaler = scaled
        ? MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3)
        : TextScaler.noScaling;
    final line = TypeTokens.bubble.copyWith(color: colors.text, height: 1.35);
    final body = DecoratedBox(
      decoration: BoxDecoration(
        color: fill ?? colors.bg,
        borderRadius: BorderRadius.all(
          Radius.circular(
            character
                ? DesignExtras.characterBubbleRadius
                : RadiusTokens.bubble,
          ),
        ),
        boxShadow: [colors.lip],
      ),
      child: Padding(
        padding:
            padding ??
            (character
                ? DesignExtras.characterBubblePadding
                : DesignExtras.bubblePadding),
        child: character
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (name case final name?)
                    Text(
                      name,
                      textScaler: scaler,
                      style: TypeTokens.label
                          .weight(700)
                          .copyWith(color: ColorTokens.inkMuted),
                    ),
                  Text(
                    text,
                    textScaler: scaler,
                    style: (quoteStyle ?? TypeTokens.quote).copyWith(
                      color: colors.text,
                    ),
                  ),
                ],
              )
            : Text(text, textScaler: TextScaler.noScaling, style: line),
      ),
    );
    final bubble = tail
        ? Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.bottomCenter,
            children: [
              body,
              Positioned(
                bottom: bubbleTailInset - DesignExtras.bubbleTail / 2,
                child: SpeechBubbleTail(variant: variant),
              ),
            ],
          )
        : body;
    return BubblePop(child: bubble);
  }
}

/// A bubble's tail, in its variant's colour. The [tipKey] goes on the
/// turned square, so its rect's bottom is the tip.
class SpeechBubbleTail extends StatelessWidget {
  const SpeechBubbleTail({required this.variant, this.tipKey, super.key});

  final SpeechBubbleVariant variant;
  final Key? tipKey;

  @override
  Widget build(BuildContext context) => Transform.rotate(
    angle: pi / 4,
    child: SizedBox.square(
      key: tipKey,
      dimension: DesignExtras.bubbleTail,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _colorsOf(variant).bg,
          borderRadius: const BorderRadius.only(
            bottomRight: Radius.circular(DesignExtras.bubbleTailRadius),
          ),
        ),
      ),
    ),
  );
}

/// Pops [child] from 0.6 to its size, from the bottom, once; under reduced
/// motion it just appears.
class BubblePop extends StatelessWidget {
  const BubblePop({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.6, end: 1),
      duration: MotionTokens.bubblePop,
      curve: MotionTokens.bubblePopCurve,
      builder: (context, scale, child) => Transform.scale(
        scale: scale,
        alignment: Alignment.bottomCenter,
        child: child,
      ),
      child: child,
    );
  }
}

class CharacterAvatar extends StatelessWidget {
  const CharacterAvatar(this.character, {this.talking = false, super.key});

  /// The art's name: `belya`, `bride_father`, …
  final String character;

  /// The mouth moves.
  final bool talking;

  /// The head-and-shoulders crop.
  static const size = Size(96, 110);

  /// The story characters' `look` numbers in `Person`
  /// (contracts/rive-characters.md "Looks").
  static const looks = {
    'usta': 18,
    'salma': 19,
    'bride_father': 20,
    'bride_mother': 21,
    'moallem': 22,
    'belya': 23,
  };

  /// Where the head's centre falls in the crop. Both arts are drawn at 1:1
  /// around it: the SVG's view box (x −70…70, y −66…90) and `Person`
  /// (200×240, its head at (100, 100)).
  static const _head = Offset(48, 55);
  static const _svg = Rect.fromLTWH(-70, -66, 140, 156);
  static const _person = Rect.fromLTWH(-100, -100, 200, 240);

  static String path(String character) =>
      'assets/illustrations/characters/$character.svg';

  @override
  Widget build(BuildContext context) {
    final svg = SvgPicture.asset(
      path(character),
      width: _svg.width,
      height: _svg.height,
      excludeFromSemantics: true,
    );
    final look = looks[character];
    final person = _person.shift(_head);
    return SizedBox.fromSize(
      size: size,
      child: Stack(
        children: [
          if (look == null)
            Positioned.fromRect(rect: _svg.shift(_head), child: svg)
          else
            Positioned.fromRect(
              rect: person,
              child: RiveArtView(
                artboard: 'Person',
                fit: rive.Fit.fill,
                bind: (model) {
                  model.number('look')?.value = look.toDouble();
                  model.boolean('talking')?.value = talking;
                },
                // The SVG, in the same place within the artboard's box.
                fallback: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fromRect(
                      rect: _svg.shift(-_person.topLeft),
                      child: svg,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
