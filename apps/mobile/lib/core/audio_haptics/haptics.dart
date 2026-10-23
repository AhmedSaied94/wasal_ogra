import 'dart:async';

import 'package:flutter/services.dart';

/// Short vibrations: a light tap for money arriving, a heavy one for a
/// fight or a bump.
abstract interface class Haptics {
  void light();

  void heavy();
}

final class SystemHaptics implements Haptics {
  const SystemHaptics();

  @override
  void light() => unawaited(HapticFeedback.lightImpact());

  @override
  void heavy() => unawaited(HapticFeedback.heavyImpact());
}
