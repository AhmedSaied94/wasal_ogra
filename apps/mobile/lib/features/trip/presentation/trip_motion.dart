// The trip screen's presentation timings (contracts/scene-layout.md
// "Motion"). They are not tunables (research R23); the ones the domain needs
// on the trip clock live there, and this file gives them as durations.
import 'package:wassal/features/trip/domain/cues.dart';
import 'package:wassal/features/trip/domain/presentation_memory.dart';

abstract final class TripMotion {
  /// The passenger glows before a throw.
  static const highlight = Duration(milliseconds: highlightMs);

  /// A bubble's pop; none under reduced motion.
  static const bubblePop = Duration(milliseconds: 150);

  /// Bump and fight; none under reduced motion.
  static const shake = Duration(milliseconds: shakeMs);

  /// The shake's reach, in points.
  static const double shakeAmplitude = 6;

  /// A walk in or out; a fade under reduced motion.
  static const walk = Duration(milliseconds: walkMs);

  /// The fare banner: in, held, out.
  static const bannerIn = Duration(milliseconds: 250);
  static const bannerHold = Duration(seconds: 3);
  static const bannerTotal = Duration(milliseconds: bannerMs);

  /// The next station's countdown pulses on this cycle while warned; a
  /// steady orange under reduced motion.
  static const countdownPulse = Duration(seconds: 1);

  /// A refused tap shakes its control.
  static const controlShake = Duration(milliseconds: 240);

  /// The driver's hand reaching toward a passenger and back.
  static const throwReach = Duration(milliseconds: 350);

  /// The street's speed in the windows, in points per second.
  static const double streetSpeed = 60;

  /// The street's share of [streetSpeed] in traffic, and on the open road.
  static const double trafficCrawl = 0.15;
  static const double openRoadRush = 3;
}
