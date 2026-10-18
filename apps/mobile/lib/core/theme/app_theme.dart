import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/tokens/colors.dart';
import 'package:wassal/core/theme/tokens/typography.dart';

/// The palette as a theme extension, so widgets read colors through the
/// theme (`context.tokens`) rather than from constants.
@immutable
class WassalTokens extends ThemeExtension<WassalTokens> {
  const WassalTokens({
    required this.shams,
    required this.hibr,
    required this.waraq,
    required this.tablouh,
    required this.primary,
    required this.danger,
    required this.gold,
    required this.badgeNew,
    required this.stations,
  });

  static const standard = WassalTokens(
    shams: ColorTokens.shams,
    hibr: ColorTokens.hibr,
    waraq: ColorTokens.waraq,
    tablouh: ColorTokens.tablouh,
    primary: ColorTokens.primary,
    danger: ColorTokens.danger,
    gold: ColorTokens.gold,
    badgeNew: ColorTokens.badgeNew,
    stations: ColorTokens.stations,
  );

  final Color shams;
  final Color hibr;
  final Color waraq;
  final Color tablouh;
  final Color primary;
  final Color danger;
  final Color gold;
  final Color badgeNew;
  final List<StationColor> stations;

  @override
  WassalTokens copyWith({
    Color? shams,
    Color? hibr,
    Color? waraq,
    Color? tablouh,
    Color? primary,
    Color? danger,
    Color? gold,
    Color? badgeNew,
    List<StationColor>? stations,
  }) => WassalTokens(
    shams: shams ?? this.shams,
    hibr: hibr ?? this.hibr,
    waraq: waraq ?? this.waraq,
    tablouh: tablouh ?? this.tablouh,
    primary: primary ?? this.primary,
    danger: danger ?? this.danger,
    gold: gold ?? this.gold,
    badgeNew: badgeNew ?? this.badgeNew,
    stations: stations ?? this.stations,
  );

  /// The app has a single theme (FR-009), so there is nothing to blend.
  @override
  WassalTokens lerp(WassalTokens? other, double t) =>
      t < 0.5 || other == null ? this : other;
}

extension WassalTokensContext on BuildContext {
  WassalTokens get tokens =>
      Theme.of(this).extension<WassalTokens>() ?? WassalTokens.standard;
}

/// The only theme: light, on شمس, in the app's two faces.
ThemeData buildAppTheme() {
  const t = WassalTokens.standard;
  final textTheme = const TextTheme(
    displayLarge: TypeTokens.display,
    displayMedium: TypeTokens.display,
    displaySmall: TypeTokens.display,
    headlineLarge: TypeTokens.headline,
    headlineMedium: TypeTokens.headline,
    headlineSmall: TypeTokens.headline,
    titleLarge: TypeTokens.title,
    titleMedium: TypeTokens.title,
    titleSmall: TypeTokens.label,
    bodyLarge: TypeTokens.body,
    bodyMedium: TypeTokens.body,
    bodySmall: TypeTokens.caption,
    labelLarge: TypeTokens.button,
    labelMedium: TypeTokens.label,
    labelSmall: TypeTokens.caption,
  ).apply(bodyColor: t.hibr, displayColor: t.hibr);

  return ThemeData(
    brightness: Brightness.light,
    colorScheme: ColorScheme(
      brightness: Brightness.light,
      primary: t.primary,
      onPrimary: t.waraq,
      secondary: t.gold,
      onSecondary: t.hibr,
      error: t.danger,
      onError: t.hibr,
      surface: t.waraq,
      onSurface: t.hibr,
    ),
    scaffoldBackgroundColor: t.shams,
    fontFamily: TypeTokens.baloo,
    textTheme: textTheme,
    extensions: const [t],
  );
}
