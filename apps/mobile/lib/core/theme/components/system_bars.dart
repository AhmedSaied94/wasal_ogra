import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';

/// The phone's system bars over what [child] draws (HANDOFF §2.4). The app
/// runs edge to edge: the status bar is clear, so the screen shows through
/// it, and the navigation bar takes [bottom], the colour of the screen's
/// own bottom edge, so three buttons never sit on a band of another colour.
/// Icons on each bar are dark on a light colour and light on a dark one.
///
/// Flutter reads the region under the middle of each bar, so the screen's
/// root sets the status bar and whatever it draws at its bottom edge (the
/// bottom nav, a sheet) sets the navigation bar. Android 7 keeps its black
/// navigation bar: its buttons can't turn dark, so Flutter leaves it alone.
class SystemBars extends StatelessWidget {
  const SystemBars({
    required this.bottom,
    required this.child,
    this.top = ColorTokens.ground,
    super.key,
  });

  /// What the screen draws under the status bar.
  final Color top;

  /// What the screen draws along its bottom edge.
  final Color bottom;
  final Widget child;

  /// The style for a screen with [top] under the status bar and [bottom]
  /// along its bottom edge.
  static SystemUiOverlayStyle style({
    required Color bottom,
    Color top = ColorTokens.ground,
  }) => SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: _iconsOn(top),
    // iOS names the bar's own brightness, not its icons'.
    statusBarBrightness: ThemeData.estimateBrightnessForColor(top),
    systemStatusBarContrastEnforced: false,
    systemNavigationBarColor: bottom,
    systemNavigationBarDividerColor: bottom,
    systemNavigationBarIconBrightness: _iconsOn(bottom),
    systemNavigationBarContrastEnforced: false,
  );

  static Brightness _iconsOn(Color color) =>
      switch (ThemeData.estimateBrightnessForColor(color)) {
        Brightness.dark => Brightness.light,
        Brightness.light => Brightness.dark,
      };

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: style(top: top, bottom: bottom),
    child: child,
  );
}
