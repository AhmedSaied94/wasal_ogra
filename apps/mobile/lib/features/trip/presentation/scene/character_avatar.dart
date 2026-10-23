// A story character outside the passenger seats (HANDOFF §3.4
// `CharacterAvatar`): `wassal.riv`'s `Person` with the character's look,
// cropped to the head and shoulders as `Tutorial` block 6 draws بلية; its
// static art from `assets/illustrations/characters/` without the file and
// under reduced motion.
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rive/rive.dart' as rive;
import 'package:wassal/core/art/rive_art.dart';

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
