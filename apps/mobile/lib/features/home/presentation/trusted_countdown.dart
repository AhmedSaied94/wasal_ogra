// Time left on trusted time (specs/013-m08-home-result, research R11,
// SC-003): the fuel pill's next liter, the out-of-fuel chip, the unlimited
// window. Each ticks on its own 1 s timer and rebuilds only itself; the
// device clock never moves it. The economy's next view, not the countdown,
// decides the state.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/economy/economy_providers.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';

/// How often a countdown looks at the clock.
const countdownTick = Duration(seconds: 1);

/// The whole minutes left until [untilMs] at [nowMs], rounded up: what a
/// screen reader hears.
int minutesLeft(int untilMs, int nowMs) {
  final ms = untilMs - nowMs;
  if (ms <= 0) return 0;
  return (ms + Duration.millisecondsPerMinute - 1) ~/
      Duration.millisecondsPerMinute;
}

/// The time left until [untilMs] as m:ss in the player's digits, through
/// [template]. Hidden from screen readers: the caller's label says it a
/// minute at a time.
class TrustedCountdown extends ConsumerStatefulWidget {
  const TrustedCountdown({
    required this.untilMs,
    this.style,
    this.template,
    super.key,
  });

  final int untilMs;

  /// The surrounding text style when null.
  final TextStyle? style;

  /// Wraps the time, as «اللتر الجاي {time}».
  final String Function(String time)? template;

  @override
  ConsumerState<TrustedCountdown> createState() => _TrustedCountdownState();
}

class _TrustedCountdownState extends ConsumerState<TrustedCountdown> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(countdownTick, (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = ref.watch(trustedClockProvider).requireValue.nowMs();
    final time = ref
        .watch(numberFormatterProvider)
        .countdown(Duration(milliseconds: widget.untilMs - now));
    return ExcludeSemantics(
      child: Text(widget.template?.call(time) ?? time, style: widget.style),
    );
  }
}

/// [builder] with the whole minutes left until [untilMs], rebuilt only when
/// that number changes: at most once a minute (research R11).
class TrustedMinutes extends ConsumerStatefulWidget {
  const TrustedMinutes({
    required this.untilMs,
    required this.builder,
    super.key,
  });

  final int untilMs;
  final Widget Function(BuildContext context, int minutes) builder;

  @override
  ConsumerState<TrustedMinutes> createState() => _TrustedMinutesState();
}

class _TrustedMinutesState extends ConsumerState<TrustedMinutes> {
  Timer? _timer;
  late int _minutes = _read();

  int _read() => minutesLeft(
    widget.untilMs,
    ref.read(trustedClockProvider).requireValue.nowMs(),
  );

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(countdownTick, (_) {
      if (!mounted) return;
      final minutes = _read();
      if (minutes != _minutes) setState(() => _minutes = minutes);
    });
  }

  @override
  void didUpdateWidget(TrustedMinutes old) {
    super.didUpdateWidget(old);
    if (old.untilMs != widget.untilMs) _minutes = _read();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _minutes);
}
