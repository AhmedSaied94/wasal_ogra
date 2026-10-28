// The first session's card screens (`Name`, and the fuel lesson drawn to
// its frame): a white card on its big lip with a character's 112 `sun`
// circle over its top, on the ground with two soft circles.
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/components/characters.dart';
import 'package:wassal/core/theme/components/containers.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';

/// The card, its [children] in a column 14 apart, with [character]'s avatar
/// overlapping its top by half.
class OnboardingCard extends StatelessWidget {
  const OnboardingCard({
    required this.character,
    required this.children,
    this.avatarKey,
    super.key,
  });

  final String character;
  final List<Widget> children;
  final Key? avatarKey;

  /// How far the avatar rises over the card.
  static const double overlap = DesignExtras.nameAvatar / 2;

  /// The space under the card on its screen. The boards centre the card
  /// between their 36 and 28; centring the avatar and the card together
  /// between 0 and this keeps the card where they have it, and the avatar
  /// on screen when the keyboard leaves little room.
  static const double screenBottom = 28 + (overlap - LayoutTokens.topInset);

  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: overlap),
        child: AppCard(
          radius: RadiusTokens.scene,
          lip: LipTokens.cardBig,
          padding: DesignExtras.nameCardPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: SpaceTokens.s14,
            children: children,
          ),
        ),
      ),
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: Center(child: OnboardingAvatar(character, key: avatarKey)),
      ),
    ],
  );
}

/// `Name` block 1a: a character in a 112 `sun` circle.
class OnboardingAvatar extends StatelessWidget {
  const OnboardingAvatar(this.character, {super.key});

  final String character;

  @override
  Widget build(BuildContext context) => Container(
    width: DesignExtras.nameAvatar,
    height: DesignExtras.nameAvatar,
    decoration: const BoxDecoration(
      color: ColorTokens.sun,
      shape: BoxShape.circle,
      boxShadow: [DesignExtras.nameAvatarLip],
    ),
    child: ClipOval(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox.square(
          dimension: DesignExtras.nameAvatarArt,
          child: FittedBox(
            alignment: Alignment.bottomCenter,
            child: CharacterAvatar(character),
          ),
        ),
      ),
    ),
  );
}

/// `Name` and `FuelLesson` block 0: two `primary.soft` circles, where the
/// boards draw them.
class OnboardingCircles extends CustomPainter {
  const OnboardingCircles();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = ColorTokens.primarySoft;
    final sx = size.width / LayoutTokens.frameW;
    final sy = size.height / LayoutTokens.frameH;
    for (final (centre, radius) in DesignExtras.nameCircles) {
      canvas.drawCircle(Offset(centre.dx * sx, centre.dy * sy), radius, paint);
    }
  }

  @override
  bool shouldRepaint(OnboardingCircles oldDelegate) => false;
}
