import 'dart:math' as math;

import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rive/rive.dart' as rive;
import 'package:wassal/core/art/rive_art.dart';
import 'package:wassal/core/art/rive_scenes.dart';
import 'package:wassal/core/theme/components/characters.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';

/// The panel's four talking Booleans for [talking]: its own on, the others
/// off; all off for nobody, or for a speaker without one
/// (specs/012.5-m22-animated-scenes, data-model.md `panelTalkers`).
Map<String, bool> panelTalkers(String? talking) => {
  for (final talker in sceneTalkers) talker: talker == talking,
};

/// A comic panel's art (specs/012-m07-onboarding/contracts/scenes.md "Panel
/// art"): the drawing the app ships for [slug], or [PanelFallback] drawn
/// from the panel's [speakers]. Art ships in the app, not in packs, so a
/// missing drawing never blocks a scene. With [animate], the scenes' file
/// draws it over the drawing, [talking] talking
/// (specs/012.5-m22-animated-scenes, contracts/rive-scenes.md "Panel art").
class PanelArt extends StatelessWidget {
  const PanelArt({
    required this.slug,
    required this.speakers,
    this.current,
    this.animate = false,
    this.talking,
    super.key,
  });

  final String slug;

  /// The panel's speakers in order; the narrator is left out.
  final List<String> speakers;

  /// Who speaks first, drawn in front by the fallback.
  final String? current;

  /// Whether to draw the panel's animation; without it, or when it can't
  /// play, the drawing.
  final bool animate;

  /// The speaker talking now, or nobody.
  final String? talking;

  /// The drawings, by slug. A new drawing is one entry and its asset
  /// (`tool/design/sync_assets.dart`).
  static const _drawings = {
    'opening_key': 'assets/illustrations/panels/opening_key.svg',
    'opening_stand': 'assets/illustrations/panels/opening_stand.svg',
    'opening_go': 'assets/illustrations/panels/opening_go.svg',
    'stand_morning': 'assets/illustrations/panels/stand_morning.svg',
    'salma_waiting': 'assets/illustrations/panels/salma_waiting.svg',
    'usta_decides': 'assets/illustrations/panels/usta_decides.svg',
    // M10's sample panel: the bride's family in the salon
    // (specs/015-m10-apartment-story, research R17).
    'ch4_mother_looks': 'assets/illustrations/panels/ch4_mother_looks.svg',
  };

  /// Content slugs that draw another slug's art, both the drawing and the
  /// animation (specs/012.5-m22-animated-scenes, data-model.md "Art slug"):
  /// the release draft's names for the سلمى scene's three panels.
  static const Map<String, String> _aliases = {
    'ch1_stand_morning': 'stand_morning',
    'ch1_salma_asks': 'salma_waiting',
    'ch1_usta_dreams': 'usta_decides',
  };

  /// The art slug [slug] draws: an alias's, else itself.
  static String artFor(String slug) => _aliases[slug] ?? slug;

  /// The asset drawn for [slug], or null when it has none.
  static String? assetFor(String slug) => _drawings[artFor(slug)];

  /// Sets all four talking Booleans for [talking], so none is left on from
  /// an earlier turn.
  static void Function(rive.ViewModelInstance model) bindTalkers(
    String? talking,
  ) => (model) {
    for (final MapEntry(key: talker, value: on) in panelTalkers(
      talking,
    ).entries) {
      model.boolean(talker)?.value = on;
    }
  };

  @override
  Widget build(BuildContext context) {
    final still = _still();
    if (!animate) return still;
    // The drawing's own fit, so a shorter panel loses sky first.
    return RiveArtView(
      source: RiveArtSource.scenes,
      artboard: artFor(slug),
      fit: rive.Fit.cover,
      alignment: Alignment.bottomCenter,
      bind: bindTalkers(talking),
      fallback: still,
    );
  }

  Widget _still() => switch (assetFor(slug)) {
    final asset? => SvgPicture.asset(
      asset,
      fit: BoxFit.cover,
      alignment: Alignment.bottomCenter,
      excludeFromSemantics: true,
    ),
    null => PanelFallback(
      speakers: [
        for (final s in speakers)
          if (s != PanelFallback.narrator) s,
      ],
      current: current,
    ),
  };
}

/// A panel without its drawing: the sky over a street strip, and each
/// speaker but the narrator as a [CharacterAvatar] at [scale], side by
/// side, the [current] one in front.
class PanelFallback extends StatelessWidget {
  const PanelFallback({required this.speakers, this.current, super.key});

  final List<String> speakers;
  final String? current;

  static const skyKey = Key('PanelFallback.sky');
  static const streetKey = Key('PanelFallback.street');

  static Key avatarKey(String character) =>
      ValueKey('PanelFallback.avatar.$character');

  static const double scale = 1.6;
  static const narrator = 'narrator';

  static const double _street = 96;
  static const double _kerb = 10;

  /// How far a figure stands into the street.
  static const double _stand = 40;

  /// Neighbours overlap by up to a quarter of a figure.
  static const double _overlap = 0.25;

  /// The figures in paint order: the others as given, the current last.
  List<String> get _figures {
    final people = <String>[];
    for (final speaker in speakers) {
      if (speaker != narrator && !people.contains(speaker)) people.add(speaker);
    }
    if (current case final c? when people.remove(c)) people.add(c);
    return people;
  }

  @override
  Widget build(BuildContext context) {
    final figures = _figures;
    final size = CharacterAvatar.size * scale;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final step = figures.length < 2
            ? 0.0
            : math.min(
                size.width * (1 - _overlap),
                (width - size.width) / (figures.length - 1),
              );
        final row = step * (figures.length - 1) + size.width;
        final left = (width - row) / 2;
        // In RTL the first speaker stands on the right.
        final rtl = Directionality.of(context) == TextDirection.rtl;
        final order = [
          for (final f in speakers)
            if (figures.contains(f)) f,
        ];
        return Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(key: skyKey, color: ColorTokens.sceneSky),
            const Positioned(
              key: streetKey,
              left: 0,
              right: 0,
              bottom: 0,
              height: _street,
              child: Column(
                children: [
                  SizedBox(
                    height: _kerb,
                    width: double.infinity,
                    child: ColoredBox(color: ColorTokens.sceneKerb),
                  ),
                  Expanded(
                    child: SizedBox(
                      width: double.infinity,
                      child: ColoredBox(color: ColorTokens.sceneRoad),
                    ),
                  ),
                ],
              ),
            ),
            for (final figure in figures)
              Positioned(
                key: avatarKey(figure),
                left: rtl
                    ? width - left - size.width - step * order.indexOf(figure)
                    : left + step * order.indexOf(figure),
                bottom: _street - _stand,
                width: size.width,
                height: size.height,
                child: FittedBox(child: CharacterAvatar(figure)),
              ),
          ],
        );
      },
    );
  }
}
