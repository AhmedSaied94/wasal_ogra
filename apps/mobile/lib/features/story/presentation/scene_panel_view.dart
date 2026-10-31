// A scene's panel as the story viewer draws it (specs/015-m10-apartment-story,
// contracts/scene-viewer.md "The viewer", HANDOFF `SceneViewer` box 4): the
// panel's art in the 540 frame, up to two character bubbles laid over it, and
// the narrator's caption. The page decides how many bubbles have shown and
// who talks (the stagger, or M22's turns); this draws them.
import 'dart:math' as math;

import 'package:content_models/content_models.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/art/panel_art.dart';
import 'package:wassal/core/theme/components/characters.dart';
import 'package:wassal/core/theme/components/story.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';

/// Places a bubble [width] wide at [top], [inset] in from the start or end
/// side, then moves it to keep [inset] inside the panel (HANDOFF: "bubbles
/// stay clamped inside the panel").
class _BubblePlace extends SingleChildLayoutDelegate {
  const _BubblePlace({
    required this.top,
    required this.width,
    required this.atStart,
    required this.inset,
    required this.textDirection,
  });

  final double top;
  final double width;
  final bool atStart;
  final double inset;
  final TextDirection textDirection;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.tightFor(
        width: math.min(width, math.max(0, constraints.maxWidth - 2 * inset)),
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final left = atStart == (textDirection == TextDirection.ltr);
    final x = left ? inset : size.width - inset - childSize.width;
    final lowest = math.max(inset, size.height - inset - childSize.height);
    return Offset(x, top.clamp(inset, lowest));
  }

  @override
  bool shouldRelayout(_BubblePlace old) =>
      old.top != top ||
      old.width != width ||
      old.atStart != atStart ||
      old.inset != inset ||
      old.textDirection != textDirection;
}

/// The speaker label for [speaker]: the player's name for `usta`, else the
/// character's name from the strings.
typedef SpeakerName = String Function(String speaker);

class ScenePanelView extends StatelessWidget {
  const ScenePanelView({
    required this.panel,
    required this.speakerName,
    this.animate = false,
    this.talking,
    this.shown,
    super.key,
  });

  final Panel panel;
  final SpeakerName speakerName;

  /// Whether the scenes' Rive file draws the panel (else its drawing).
  final bool animate;

  /// The speaker talking now, or nobody.
  final String? talking;

  /// How many of the spoken lines have shown their bubble; null for all.
  final int? shown;

  /// The panel's frame: 358×540 on the reference phone.
  static const double frameWidth = 358;
  static const double frameHeight = 540;
  static const Size frame = Size(frameWidth, frameHeight);

  static const captionKey = Key('ScenePanelView.caption');
  static Key bubbleKey(int i) => ValueKey('ScenePanelView.bubble.$i');

  /// Box 6 and box 10: the first bubble at the start side, 120 down and 190
  /// wide; the second at the end side, 236 down and 180 wide; both 12 in.
  static const double _inset = 12;
  static const double _firstTop = 120;
  static const double _firstWidth = 190;
  static const double _secondTop = 236;
  static const double _secondWidth = 180;

  /// The caption's corner, as `ComicPanel` draws it.
  static const double _captionInset = 14;

  /// Box 6's padding, 8 14 10, in place of the tutorial bubble's.
  static const _bubblePadding = EdgeInsets.fromLTRB(14, 8, 14, 10);

  /// The panel's spoken lines (V-C12: at most two), in authored order.
  List<PanelLine> get spoken => [
    for (final line in panel.lines)
      if (line.speaker != PanelFallback.narrator) line,
  ];

  /// The narrator's line, the panel's caption.
  String? get caption {
    for (final line in panel.lines) {
      if (line.speaker == PanelFallback.narrator) return line.text.arEg;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(RadiusTokens.scene);
    final lines = spoken;
    final speakers = [for (final line in panel.lines) line.speaker];
    final caption = this.caption;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: PanelArt.groundFor(panel.art),
        borderRadius: radius,
        boxShadow: const [LipTokens.dark],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            PanelArt(
              slug: panel.art,
              speakers: speakers,
              current: lines.isEmpty ? null : lines.first.speaker,
              animate: animate,
              talking: talking,
            ),
            if (caption != null)
              PositionedDirectional(
                top: _captionInset,
                end: _captionInset,
                child: ComicCaption(caption, key: captionKey),
              ),
            for (final (i, line) in lines.indexed)
              Positioned.fill(
                child: CustomSingleChildLayout(
                  // The first stands at the start side, the second at the
                  // end; both stay inside the panel.
                  delegate: _BubblePlace(
                    top: i == 0 ? _firstTop : _secondTop,
                    width: i == 0 ? _firstWidth : _secondWidth,
                    atStart: i == 0,
                    inset: _inset,
                    textDirection: Directionality.of(context),
                  ),
                  child: _turn(
                    key: ValueKey(i),
                    shown: shown == null || i < shown!,
                    bubble: SpeechBubble(
                      key: bubbleKey(i),
                      variant: SpeechBubbleVariant.character,
                      name: speakerName(line.speaker),
                      text: line.text.arEg,
                      padding: _bubblePadding,
                      quoteStyle: DesignExtras.sceneBubbleLine,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// [bubble] in its turn: popping in once shown (the bubble pops itself
  /// when built), and until then in its place, unseen, untouchable and still
  /// read, so a screen reader meets the lines in authored order.
  static Widget _turn({
    required Key key,
    required bool shown,
    required Widget bubble,
  }) => shown
      ? KeyedSubtree(
          key: key,
          child: MergeSemantics(child: bubble),
        )
      : IgnorePointer(
          key: key,
          child: Opacity(
            opacity: 0,
            alwaysIncludeSemantics: true,
            child: MergeSemantics(child: bubble),
          ),
        );
}
