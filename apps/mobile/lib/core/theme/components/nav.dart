import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/components/app_icon.dart';
import 'package:wassal/core/theme/components/pills.dart';
import 'package:wassal/core/theme/components/pressable.dart';
import 'package:wassal/core/theme/components/system_bars.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

/// Navigation (HANDOFF §3.3, `Components` boxes 175–185).

/// The four tabs: الموقف، الخطوط، الشقة، المحل, right to left. White, 88
/// high plus the phone's bottom inset, the nav lip upward. The active tab
/// shows its glyph white in a 60×34 `primary` pill, fading in over 150 ms;
/// the others are `icon.off` with `ink.muted` labels. Each whole cell is
/// the touch target.
class BottomNav extends StatelessWidget {
  const BottomNav({
    required this.currentIndex,
    required this.onTap,
    this.newDots = const [false, false, false, false],
    this.disabled = const [false, false, false, false],
    super.key,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  /// Which tabs show the new-dot, in tab order.
  final List<bool> newDots;

  /// Which tabs need the network while there is none, in tab order: drawn
  /// at [Pressable.disabledOpacity], taking no tap, and said so
  /// («المحل، محتاج نت»).
  final List<bool> disabled;

  static Key cellKey(int index) => ValueKey('BottomNav.cell.$index');

  /// Each cell's pill, shown only on the active one.
  static const pillKey = Key('BottomNav.pill');

  static const double _top = SpaceTokens.s8;
  static const double _side = 10;
  static const double _gap = SpaceTokens.s4;

  /// Home and apartment have their own active art; the others turn white.
  static const _tabs = [
    (icon: 'nav_home', active: 'nav_home_active'),
    (icon: 'nav_lines', active: null),
    (icon: 'nav_apartment', active: 'nav_apartment_active'),
    (icon: 'nav_shop', active: null),
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final labels = [
      l10n.tabHome,
      l10n.tabLines,
      l10n.tabApartment,
      l10n.tabShop,
    ];
    // Under the navigation bar too (SystemBars).
    return SystemBars(
      bottom: ColorTokens.paper,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: ColorTokens.paper,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(DesignExtras.navRadius),
          ),
          boxShadow: [LipTokens.nav],
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            _side,
            _top,
            _side,
            MediaQuery.viewPaddingOf(context).bottom,
          ),
          child: SizedBox(
            height: LayoutTokens.bottomNav - _top,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: _gap,
              children: [
                for (final (i, tab) in _tabs.indexed)
                  Expanded(
                    child: _NavCell(
                      key: cellKey(i),
                      icon: tab.icon,
                      activeIcon: tab.active,
                      label: labels[i],
                      newLabel: l10n.newBadgeLabel,
                      offlineLabel: l10n.navNeedsNetwork,
                      active: i == currentIndex,
                      showDot: i < newDots.length && newDots[i],
                      enabled: i >= disabled.length || !disabled[i],
                      onTap: () => onTap(i),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavCell extends StatelessWidget {
  const _NavCell({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.newLabel,
    required this.offlineLabel,
    required this.active,
    required this.showDot,
    required this.enabled,
    required this.onTap,
    super.key,
  });

  final String icon;
  final String? activeIcon;
  final String label;
  final String newLabel;
  final String offlineLabel;
  final bool active;
  final bool showDot;
  final bool enabled;
  final VoidCallback onTap;

  static const double _height = 62;
  static const double _icon = 24;

  /// `Components` boxes 182–183: the dot's place against the icon.
  static const double _dotTop = -7.5;
  static const double _dotEnd = -10.8;

  @override
  Widget build(BuildContext context) {
    final fade = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : DesignExtras.tabFade;
    const pill = DesignExtras.navPill;
    final l10n = AppLocalizations.of(context);
    return Pressable(
      onTap: onTap,
      enabled: enabled,
      selected: active,
      semanticLabel: switch ((enabled, showDot)) {
        (false, _) => l10n.pairLabel(label, offlineLabel),
        (true, true) => l10n.pairLabel(label, newLabel),
        (true, false) => label,
      },
      child: SizedBox(
        width: double.infinity,
        height: _height,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: SpaceTokens.s2,
          children: [
            SizedBox.fromSize(
              size: pill,
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  AnimatedOpacity(
                    opacity: active ? 1 : 0,
                    duration: fade,
                    child: Container(
                      key: BottomNav.pillKey,
                      width: pill.width,
                      height: pill.height,
                      decoration: BoxDecoration(
                        color: ColorTokens.primary,
                        borderRadius: BorderRadius.circular(RadiusTokens.pill),
                      ),
                    ),
                  ),
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      AppIcon(
                        active ? (activeIcon ?? icon) : icon,
                        size: _icon,
                        color: active ? ColorTokens.paper : ColorTokens.iconOff,
                      ),
                      if (showDot)
                        const PositionedDirectional(
                          top: _dotTop,
                          end: _dotEnd,
                          child: NewDot(),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: active
                  ? DesignExtras.navLabel
                        .weight(700)
                        .copyWith(color: ColorTokens.primary)
                  : DesignExtras.navLabel.copyWith(color: ColorTokens.inkMuted),
            ),
          ],
        ),
      ),
    );
  }
}

/// A daily entry on الموقف (`C-Home` boxes 19–37): a 46 circle with a 26
/// icon and the bubble lip, white (or the first station's colour for an
/// [event]), its label on a white chip under it, and an optional new-dot or
/// [count] badge at the circle's top-end corner. The tap area is 58×65.
class DailyCircle extends StatelessWidget {
  const DailyCircle({
    required this.icon,
    required this.label,
    required this.onTap,
    this.event = false,
    this.isNew = false,
    this.count,
    this.semanticLabel,
    super.key,
  });

  final String icon;
  final String label;
  final VoidCallback onTap;
  final bool event;
  final bool isNew;

  /// Preformatted, for example «٢/٣».
  final String? count;

  /// What a screen reader says, for example «مهام اليوم، خلصت ٢ من ٣».
  final String? semanticLabel;

  static const circleKey = Key('DailyCircle.circle');
  static const Size tapArea = Size(58, 65);
  static const double size = 46;
  static const double _icon = 26;
  static const double _chip = 16;
  static const double _gap = 3;

  /// `C-Home` boxes 23 and 28: the dot's and the badge's place.
  static const double _dotEnd = 5;
  static const double _badgeTop = -4;
  static const double _badgeEnd = -2;

  @override
  Widget build(BuildContext context) {
    final count = this.count;
    return Pressable(
      onTap: onTap,
      pressedOpacity: 0.7,
      semanticLabel: semanticLabel ?? label,
      child: SizedBox.fromSize(
        size: tapArea,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Align(
              alignment: Alignment.topCenter,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                spacing: _gap,
                children: [
                  Container(
                    key: circleKey,
                    width: size,
                    height: size,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: event
                          ? StationColors.all.first.bg
                          : ColorTokens.paper,
                      shape: BoxShape.circle,
                      boxShadow: const [LipTokens.bubble],
                    ),
                    child: AppIcon(
                      icon,
                      size: _icon,
                      color: event ? ColorTokens.paper : ColorTokens.ink,
                    ),
                  ),
                  Container(
                    height: _chip,
                    padding: const EdgeInsets.symmetric(
                      horizontal: SpaceTokens.s6,
                    ),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: ColorTokens.paper,
                      borderRadius: BorderRadius.circular(RadiusTokens.pill),
                    ),
                    child: Text(
                      label,
                      maxLines: 1,
                      softWrap: false,
                      style: TypeTokens.label.copyWith(color: ColorTokens.ink),
                    ),
                  ),
                ],
              ),
            ),
            if (isNew)
              const PositionedDirectional(
                top: 0,
                end: _dotEnd,
                child: NewDot(),
              ),
            if (count != null)
              PositionedDirectional(
                top: _badgeTop,
                end: _badgeEnd,
                child: CountBadge(text: count),
              ),
          ],
        ),
      ),
    );
  }
}
