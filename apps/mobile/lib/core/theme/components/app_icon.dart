import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';

/// One of the design's icons, `assets/icons/<name>.svg` (synced from
/// `docs/design/icons/`). Mono icons draw in `currentColor`, which [color]
/// sets; multi-colour icons (coin, bonat, fuel, warning, …) keep their own
/// colours whatever [color] is (HANDOFF §2.5).
class AppIcon extends StatelessWidget {
  const AppIcon(this.name, {this.size = 24, this.color, super.key});

  final String name;
  final double size;
  final Color? color;

  static String path(String name) => 'assets/icons/$name.svg';

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    path(name),
    width: size,
    height: size,
    theme: SvgTheme(
      currentColor: color ?? DefaultTextStyle.of(context).style.color!,
    ),
    excludeFromSemantics: true,
  );
}
