import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';

/// The only theme: light, on the `ground`, in Readex Pro with Marhey for
/// display (specs/008.5-m21-design-refresh, contracts/design-tokens.md
/// "Theme"). Presses show the lip, not an ink splash.
ThemeData buildAppTheme() {
  final textTheme = const TextTheme(
    displayLarge: TypeTokens.displayXl,
    displayMedium: TypeTokens.displayL,
    displaySmall: TypeTokens.displayM,
    headlineLarge: TypeTokens.displayL,
    headlineMedium: TypeTokens.displayM,
    headlineSmall: TypeTokens.displayS,
    titleLarge: TypeTokens.displayS,
    titleMedium: TypeTokens.row,
    titleSmall: TypeTokens.label,
    bodyLarge: TypeTokens.row,
    bodyMedium: TypeTokens.body,
    bodySmall: TypeTokens.caption,
    labelLarge: TypeTokens.buttonL,
    labelMedium: TypeTokens.label,
    labelSmall: TypeTokens.label,
  ).apply(bodyColor: ColorTokens.ink, displayColor: ColorTokens.ink);
  final clear = ColorTokens.ink.withValues(alpha: 0);

  return ThemeData(
    brightness: Brightness.light,
    colorScheme: const ColorScheme(
      brightness: Brightness.light,
      primary: ColorTokens.primary,
      onPrimary: ColorTokens.paper,
      secondary: ColorTokens.gold,
      onSecondary: ColorTokens.ink,
      error: ColorTokens.danger,
      onError: ColorTokens.ink,
      surface: ColorTokens.paper,
      onSurface: ColorTokens.ink,
    ),
    scaffoldBackgroundColor: ColorTokens.ground,
    fontFamily: TypeTokens.readexPro,
    textTheme: textTheme,
    splashFactory: NoSplash.splashFactory,
    highlightColor: clear,
    hoverColor: clear,
    extensions: const [WassalTokens.standard],
  );
}
