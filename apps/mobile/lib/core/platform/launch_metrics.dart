import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// Tells Android when the first usable screen has drawn, so `Fully drawn`
/// in logcat marks the end of cold start (FR-012a, research R13).
abstract final class LaunchMetrics {
  static const _channel = MethodChannel('wassal/launch');
  static bool _reported = false;

  /// Reports once per process; later calls do nothing.
  static Future<void> reportFullyDrawnOnce() async {
    if (_reported) return;
    _reported = true;
    try {
      await _channel.invokeMethod<void>('reportFullyDrawn');
    } on MissingPluginException {
      // iOS and tests register no handler; there is nothing to report to.
    }
  }

  @visibleForTesting
  static void resetForTest() => _reported = false;
}

/// Reports fully drawn after [child]'s first frame.
class ReportFullyDrawn extends StatefulWidget {
  const ReportFullyDrawn({required this.child, super.key});

  final Widget child;

  @override
  State<ReportFullyDrawn> createState() => _ReportFullyDrawnState();
}

class _ReportFullyDrawnState extends State<ReportFullyDrawn> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(LaunchMetrics.reportFullyDrawnOnce()),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
