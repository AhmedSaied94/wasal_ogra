// A passenger's face in a circle (specs/013-m08-home-result, research R25):
// the result's mistakes and quote, the share picture and the pre-trip card's
// new type. `wassal.riv`'s `Person` with the look's number, cropped to the
// head as the artboards' avatars are, and held still: a face in a list has
// no idle loop. The look's SVG without the file and under reduced motion.
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rive/rive.dart' as rive;
import 'package:wassal/core/art/rive_art.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';

/// The sizes the artboards draw a passenger's face at.
enum PassengerAvatarSize {
  /// `Result` box 35: a mistake's line.
  mistake(38),

  /// `ShareCard` box 9: the quote on the picture.
  share(46),

  /// `Result` box 19: the quote.
  quote(50),

  /// `PreTrip` box 30: the new type.
  newCard(60);

  const PassengerAvatarSize(this.side);

  final double side;
}

class PassengerAvatar extends StatelessWidget {
  const PassengerAvatar({
    required this.lookId,
    required this.person,
    required this.size,
    this.mistake = false,
    super.key,
  });

  /// The look's art id (`hagga`, `student`, …).
  final String lookId;

  /// Its `look` number in `Person`.
  final int person;
  final PassengerAvatarSize size;

  /// On `danger.soft`, for a mistake's line; else on `ground`.
  final bool mistake;

  /// The window the circle shows, in the rig's units around the head's
  /// centre: the artboards' avatar `viewBox` (−60 −62 120 120).
  static const _window = Rect.fromLTWH(-60, -62, 120, 120);

  /// The passenger SVGs' view box, and `Person`'s 200×240 with its head at
  /// (100, 100), both in the same units.
  static const _svg = Rect.fromLTWH(-70, -66, 140, 156);
  static const _person = Rect.fromLTWH(-100, -100, 200, 240);

  static String path(String lookId) =>
      'assets/illustrations/passengers/$lookId.svg';

  /// [rect] in the circle's coordinates, at [scale].
  static Rect _place(Rect rect, double scale) => Rect.fromLTWH(
    (rect.left - _window.left) * scale,
    (rect.top - _window.top) * scale,
    rect.width * scale,
    rect.height * scale,
  );

  @override
  Widget build(BuildContext context) {
    final side = size.side;
    final scale = side / _window.width;
    final svg = SvgPicture.asset(
      path(lookId),
      width: _svg.width * scale,
      height: _svg.height * scale,
      excludeFromSemantics: true,
    );
    final personRect = _place(_person, scale);
    final svgRect = _place(_svg, scale);
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: side,
        child: ClipOval(
          child: ColoredBox(
            color: mistake ? ColorTokens.dangerSoft : ColorTokens.ground,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fromRect(
                  rect: personRect,
                  // A still face: Rive draws its first frame and stops.
                  child: TickerMode(
                    enabled: false,
                    child: RiveArtView(
                      artboard: 'Person',
                      fit: rive.Fit.fill,
                      bind: (model) =>
                          model.number('look')?.value = person.toDouble(),
                      fallback: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned.fromRect(
                            rect: svgRect.shift(-personRect.topLeft),
                            child: svg,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
