import 'package:wassal/core/theme/tokens/design_tokens.dart';

/// How a comic panel's lines take their turns
/// (specs/012.5-m22-animated-scenes, research R5): each speaker talks while
/// their bubble goes up, for about 60 ms a letter of the line, between a
/// floor and a ceiling, a short pause between speakers. These are that
/// spec's own defaults, not values measured from an artboard, which is why
/// they aren't in `DesignExtras`. They are presentation values, not
/// balancing numbers, so they have no Remote Config key.
abstract final class SceneTurnTokens {
  /// The first turn starts once the panel has slid in.
  static const leadIn = MotionTokens.sheetIn;

  /// About 16 letters a second, an unhurried reading pace.
  static const perLetter = Duration(milliseconds: 60);

  /// A short line still gets a few flaps of the 0.5 s `talk` loop.
  static const min = Duration(milliseconds: 1200);

  /// A long line doesn't hold the next speaker back for long.
  static const max = Duration(milliseconds: 4000);

  /// A beat between speakers, so the change of speaker shows.
  static const pause = Duration(milliseconds: 300);
}
