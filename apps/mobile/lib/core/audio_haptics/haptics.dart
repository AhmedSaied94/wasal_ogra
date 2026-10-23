import 'dart:async';

import 'package:flutter/services.dart';

/// Short vibrations: a light tap for money arriving, a heavy one for a
/// fight or a bump, and a selection tick for a button press.
abstract interface class Haptics {
  void light();

  void heavy();

  /// A press on any control (HANDOFF §2.3; specs/008.5-m21-design-refresh,
  /// research R4).
  void selection();
}

final class SystemHaptics implements Haptics {
  const SystemHaptics();

  @override
  void light() => unawaited(HapticFeedback.lightImpact());

  @override
  void heavy() => unawaited(HapticFeedback.heavyImpact());

  @override
  void selection() => unawaited(HapticFeedback.selectionClick());
}
