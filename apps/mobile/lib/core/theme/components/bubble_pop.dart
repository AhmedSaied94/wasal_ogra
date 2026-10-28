// The design's bubble pop (the `bubblePop` motion token), shared by
// `SpeechBubble` and `ComicPanel`'s bubbles in turn
// (specs/012.5-m22-animated-scenes, research R7).
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';

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
