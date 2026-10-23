// The driver's hand (layer 3, `C-Trip` boxes 50–53): the sleeve rising
// from under the dashboard, the forearm, the palm at `SceneLayout.hand` and
// the thumb. It reaches toward a passenger on a throw. What it holds is the
// `inHand` money note, a Flutter overlay at the same point.
import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/trip/presentation/scene/scene_space.dart';
import 'package:wassal/features/trip/presentation/scene/trip_game.dart';
import 'package:wassal/features/trip/presentation/trip_motion.dart';

class HandComponent extends Component with HasGameReference<TripGame> {
  String? _target;
  double _startMs = 0;

  /// Reaches toward [passengerId], from [clockMs] on the trip clock.
  void reach(String passengerId, double clockMs) {
    _target = passengerId;
    _startMs = clockMs;
  }

  /// How far the palm is from its rest now.
  Offset _reach() {
    final layout = game.layout;
    final view = game.view;
    final target = _target;
    if (layout == null || view == null || target == null) return Offset.zero;
    final t = (game.clockMs - _startMs) / TripMotion.throwReach.inMilliseconds;
    final seat = layout.seats[view.passenger(target)?.seatId];
    if (t >= 1) _target = null;
    if (t < 0 || t >= 1 || seat == null) return Offset.zero;
    // Out and back.
    final k = math.sin(t * math.pi) * 0.35;
    return Offset(
      (seat.tokenAnchor.x - layout.hand.x) * k,
      (seat.tokenAnchor.y - layout.hand.y) * k,
    );
  }

  @override
  void render(Canvas canvas) {
    final layout = game.layout;
    if (layout == null || game.view == null) return;
    final reach = _reach();
    // The elbow follows a little, the sleeve's foot not at all.
    final elbow = reach * 0.3;
    Paint limb(Color color, double width) => Paint()
      ..color = color
      ..strokeWidth = layout.across(width)
      ..strokeCap = StrokeCap.round;
    canvas
      ..drawLine(
        layout.at(118, 500),
        layout.at(134, 456) + elbow,
        limb(ColorTokens.paper, 32),
      )
      ..drawLine(
        layout.at(128, 470) + elbow,
        layout.at(160, 404) + reach,
        limb(DesignExtras.driverSkin, 23),
      )
      ..drawCircle(
        layout.at(162, 398) + reach,
        layout.across(15),
        Paint()..color = DesignExtras.driverSkin,
      )
      ..drawOval(
        Rect.fromCenter(
          center: layout.at(155, 385) + reach,
          width: layout.across(12),
          height: layout.across(18),
        ),
        Paint()..color = DesignExtras.driverThumb,
      );
  }
}
