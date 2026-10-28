// The trip screen's presentation timings (specs/008.5-m21-design-refresh,
// contracts/trip-layout.md "Motion"). They come from `MotionTokens` and the
// design's extras; they are not tunables (M02 research R23). The ones the
// domain needs on the trip clock live there, and this file gives them as
// durations.
import 'dart:math' as math;

import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/trip/domain/cues.dart';
import 'package:wassal/features/trip/domain/presentation_memory.dart';
import 'package:wassal/features/trip/domain/projection.dart';

abstract final class TripMotion {
  /// The passenger glows before a throw.
  static const highlight = Duration(milliseconds: highlightMs);

  /// A bubble's pop from its tail; none under reduced motion.
  static const bubblePop = MotionTokens.bubblePop;
  static const bubblePopCurve = MotionTokens.bubblePopCurve;

  /// A `hot` station tag beats 1 ↔ 1.18 on this cycle; a steady ring under
  /// reduced motion.
  static const hotPulse = MotionTokens.hotTagPulse;
  static final double hotPulseAmplitude =
      MotionTokens.hotTagPulseScale.last - MotionTokens.hotTagPulseScale.first;

  /// Bump and fight; none under reduced motion.
  static const shake = MotionTokens.screenShake;

  /// The shake's reach, in points.
  static const double shakeAmplitude = MotionTokens.screenShakeAmplitude;

  /// The static art's idle bob: up 2 pt and back on this cycle (research
  /// R17); none under reduced motion.
  static const artBob = Duration(milliseconds: 1200);
  static const double artBobReach = 2;

  /// The static art's head tilt while asleep, in radians (18°).
  static const double artSleepTilt = 18 * math.pi / 180;

  /// A walk in or out (getting off rises 12 and fades); a fade under
  /// reduced motion.
  static const walk = Duration(milliseconds: walkMs);
  static const double alightRise = -MotionTokens.alightDy;

  /// The fare banner: in, held, out, on the trip clock (the domain's
  /// [bannerMs] is their sum).
  static const bannerIn = MotionTokens.toast;
  static const bannerHold = DesignExtras.bannerHold;
  static const bannerTotal = Duration(milliseconds: bannerMs);

  /// The next stop's countdown chip pulses on this beat under
  /// [countdownPulseBelow]; steady under reduced motion.
  static const countdownPulse = DesignExtras.countdownPulse;
  static const countdownPulseBelow = Duration(seconds: 8);

  /// Reputation under this share shows in `danger` with its chip.
  static const reputationLowPercent = reputationLowBelow;

  /// A refused tap shakes its control.
  static const controlShake = Duration(milliseconds: 240);

  /// The driver's hand reaching toward a passenger and back.
  static const throwReach = Duration(milliseconds: 350);

  /// The next station's sign grows from this share of its size to all of
  /// it, so the name on it never drops under 12 pt (13 pt at full size;
  /// constitution XI).
  static const double signGrowFrom = 12 / 13;

  /// بلية's coach (M07 contracts/coach.md "Motion"): the scrim fades in,
  /// and the hole moves to the next target; it jumps under reduced motion.
  static const coachScrimFade = Duration(milliseconds: 200);
  static const coachHoleMove = Duration(milliseconds: 250);
  static const coachHoleCurve = MotionTokens.sheetInCurve;

  /// The street's speed in the windows, in points per second.
  static const double streetSpeed = 60;

  /// The street's share of [streetSpeed] in traffic, and on the open road.
  static const double trafficCrawl = 0.15;
  static const double openRoadRush = 3;
}
