import 'dart:async';

import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/components/overlays.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

/// How long after the first back press on الموقف a second one leaves.
const exitWindow = Duration(seconds: 2);

/// Phone back at a tab's root (FR-021, research R7). go_router offers back
/// to the branch navigator first, so this sees it only at a tab root:
/// - on another tab, it switches to الموقف;
/// - on الموقف, the first press warns, and a second press within
///   [exitWindow] leaves the app.
class BackToExit extends StatefulWidget {
  const BackToExit({
    required this.navigationShell,
    required this.child,
    super.key,
  });

  final StatefulNavigationShell navigationShell;
  final Widget child;

  @override
  State<BackToExit> createState() => _BackToExitState();
}

class _BackToExitState extends State<BackToExit> {
  Timer? _window;

  @override
  void dispose() {
    _window?.cancel();
    super.dispose();
  }

  void _onBack(bool didPop, Object? _) {
    if (didPop) return;
    final shell = widget.navigationShell;
    if (shell.currentIndex != 0) {
      shell.goBranch(0);
      return;
    }
    final window = _window;
    if (window != null && window.isActive) {
      window.cancel();
      unawaited(SystemNavigator.pop());
      return;
    }
    _window = Timer(exitWindow, () {});
    showAppToast(
      context,
      AppLocalizations.of(context).pressBackAgainToExit,
      hold: exitWindow,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: _onBack,
      child: widget.child,
    );
  }
}
