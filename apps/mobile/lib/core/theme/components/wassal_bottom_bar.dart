import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/app_theme.dart';
import 'package:wassal/core/theme/components/new_dot.dart';
import 'package:wassal/core/theme/tokens/shape.dart';
import 'package:wassal/core/theme/tokens/space.dart';
import 'package:wassal/core/theme/tokens/typography.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

/// The four-tab bar: الموقف، الخطوط، الشقة، المحل, laid out right to left
/// (FR-014). Each whole cell is the touch target.
class WassalBottomBar extends StatelessWidget {
  const WassalBottomBar({
    required this.currentIndex,
    required this.onTap,
    this.newDots = const [false, false, false, false],
    super.key,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  /// Which tabs show the «new» dot, in tab order (FR-016a).
  final List<bool> newDots;

  static Key cellKey(int index) => ValueKey('wassal-bottom-bar-cell-$index');

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Placeholder icons until the tab art lands with the real screens.
    final tabs = [
      (icon: Icons.directions_bus_rounded, label: l10n.tabHome),
      (icon: Icons.route_rounded, label: l10n.tabLines),
      (icon: Icons.chair_rounded, label: l10n.tabApartment),
      (icon: Icons.storefront_rounded, label: l10n.tabShop),
    ];
    return ColoredBox(
      color: context.tokens.tablouh,
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            for (final (i, tab) in tabs.indexed)
              Expanded(
                child: _BarCell(
                  key: cellKey(i),
                  icon: tab.icon,
                  label: tab.label,
                  selected: i == currentIndex,
                  showDot: i < newDots.length && newDots[i],
                  onTap: () => onTap(i),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BarCell extends StatelessWidget {
  const _BarCell({
    required this.icon,
    required this.label,
    required this.selected,
    required this.showDot,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool showDot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final color = selected ? tokens.shams : tokens.waraq;
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: ShapeTokens.minTouch),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: SpaceTokens.s),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(icon, color: color),
                    if (showDot)
                      // The icon's top-end corner: top-left in RTL.
                      const PositionedDirectional(
                        top: -ShapeTokens.badgeSize / 4,
                        end: -ShapeTokens.badgeSize / 4,
                        child: NewDot(),
                      ),
                  ],
                ),
                const SizedBox(height: SpaceTokens.xs),
                Text(
                  label,
                  maxLines: 1,
                  style: TypeTokens.label.copyWith(color: color),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
