import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/components/app_icon.dart';
import 'package:wassal/core/theme/components/pressable.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

/// A button's size: the 64-high CTA, the 54–58 button, or the 44-high
/// compact one (the trip's call button, choices).
enum AppButtonSize { xl, l, compact }

enum _Variant { primary, secondary, sun, danger, tertiary }

/// The design's buttons (HANDOFF §3.1, `Components` boxes 3–21). Each is a
/// [Pressable] with its variant's fill, lip and label; disabled at 45% with
/// no lip; loading shows three pulsing dots and takes no tap. A [trailing]
/// widget (a [CostChip]) sits at the end side of the label.
class AppButton extends StatelessWidget {
  const AppButton.primary({
    required this.label,
    required this.onTap,
    this.size = AppButtonSize.xl,
    this.leading,
    this.trailing,
    this.loading = false,
    this.enabled = true,
    this.semanticLabel,
    this.expand = true,
    this.height,
    this.radius,
    this.labelStyle,
    this.sidePadding,
    super.key,
  }) : _variant = _Variant.primary;

  const AppButton.secondary({
    required this.label,
    required this.onTap,
    this.size = AppButtonSize.l,
    this.leading,
    this.trailing,
    this.loading = false,
    this.enabled = true,
    this.semanticLabel,
    this.expand = true,
    this.height,
    this.radius,
    this.labelStyle,
    this.sidePadding,
    super.key,
  }) : _variant = _Variant.secondary;

  const AppButton.sun({
    required this.label,
    required this.onTap,
    this.size = AppButtonSize.compact,
    this.leading,
    this.trailing,
    this.loading = false,
    this.enabled = true,
    this.semanticLabel,
    this.expand = true,
    this.height,
    this.radius,
    this.labelStyle,
    this.sidePadding,
    super.key,
  }) : _variant = _Variant.sun;

  const AppButton.danger({
    required this.label,
    required this.onTap,
    this.size = AppButtonSize.xl,
    this.leading,
    this.trailing,
    this.loading = false,
    this.enabled = true,
    this.semanticLabel,
    this.expand = true,
    this.height,
    this.radius,
    this.labelStyle,
    this.sidePadding,
    super.key,
  }) : _variant = _Variant.danger;

  /// Text only, in `primary`; pressed = 70% opacity.
  const AppButton.tertiary({
    required this.label,
    required this.onTap,
    this.enabled = true,
    this.semanticLabel,
    this.expand = false,
    this.height,
    this.labelStyle,
    super.key,
  }) : _variant = _Variant.tertiary,
       size = AppButtonSize.compact,
       leading = null,
       trailing = null,
       loading = false,
       radius = null,
       sidePadding = null;

  final String label;
  final VoidCallback? onTap;
  final AppButtonSize size;

  /// At the start side of the label (an icon, as on `Fail`'s revive).
  final Widget? leading;
  final Widget? trailing;
  final bool loading;
  final bool enabled;

  /// What a screen reader says; [label] by default.
  final String? semanticLabel;

  /// Fills the width it is given (the default, except for tertiary, which
  /// then centres its label).
  final bool expand;

  /// Overrides the size's height, where an artboard draws another one. A
  /// tertiary button is as high as its label unless given one.
  final double? height;

  /// Overrides the size's corner radius, where an artboard draws another one.
  final double? radius;

  /// Overrides the size's label style, where an artboard draws another one.
  final TextStyle? labelStyle;

  /// Overrides the 16 pt on each side of the label, where an artboard draws
  /// another one.
  final double? sidePadding;

  final _Variant _variant;

  /// Finds the loading dots in tests.
  static const loadingDotsKey = Key('AppButton.loadingDots');

  static const _heights = {
    AppButtonSize.xl: LayoutTokens.ctaH,
    AppButtonSize.l: DesignExtras.buttonLHeight,
    AppButtonSize.compact: LayoutTokens.touchMin,
  };

  static const _radii = {
    AppButtonSize.xl: LayoutTokens.ctaRadius,
    AppButtonSize.l: LayoutTokens.buttonRadius,
    AppButtonSize.compact: DesignExtras.compactButtonRadius,
  };

  static const _tertiaryOpacity = 0.7;

  @override
  Widget build(BuildContext context) {
    final look = _look();
    final text = Text(
      label,
      textAlign: TextAlign.center,
      maxLines: 2,
      style: (labelStyle ?? look.label).copyWith(color: look.ink),
    );
    final content = loading
        ? _LoadingDots(key: loadingDotsKey, color: look.ink)
        : Row(
            mainAxisSize: MainAxisSize.min,
            spacing: SpaceTokens.s8,
            children: [
              ?leading,
              Flexible(child: text),
              ?trailing,
            ],
          );
    if (_variant == _Variant.tertiary) {
      return Pressable(
        onTap: onTap,
        enabled: enabled,
        pressedOpacity: _tertiaryOpacity,
        semanticLabel: semanticLabel ?? label,
        child: SizedBox(
          width: expand ? double.infinity : null,
          height: height,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: SpaceTokens.s8),
            child: expand ? Center(child: content) : content,
          ),
        ),
      );
    }
    final corners = BorderRadius.circular(radius ?? _radii[size]!);
    return Pressable(
      onTap: loading ? null : onTap,
      enabled: enabled,
      lip: look.lip,
      borderRadius: corners,
      semanticLabel: semanticLabel ?? label,
      child: SizedBox(
        width: expand ? double.infinity : null,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: look.fill,
            borderRadius: corners,
            border: look.ring,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: height ?? _heights[size]!),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: sidePadding ?? SpaceTokens.s16,
              ),
              child: Center(widthFactor: 1, heightFactor: 1, child: content),
            ),
          ),
        ),
      ),
    );
  }

  _Look _look() => switch (_variant) {
    _Variant.primary => _Look(
      fill: ColorTokens.primary,
      ink: ColorTokens.paper,
      lip: switch (size) {
        AppButtonSize.xl => LipTokens.primary,
        AppButtonSize.l => LipTokens.primaryM,
        AppButtonSize.compact => LipTokens.primaryS,
      },
      label: _label(),
    ),
    _Variant.secondary => _Look(
      fill: ColorTokens.paper,
      ink: ColorTokens.ink,
      lip: switch (size) {
        AppButtonSize.xl => LipTokens.cardBig,
        AppButtonSize.l => LipTokens.card,
        AppButtonSize.compact => LipTokens.cardSmall,
      },
      ring: Border.all(
        color: RingTokens.empty.color,
        width: RingTokens.empty.width,
        strokeAlign: BorderSide.strokeAlignInside,
      ),
      label: _label(),
    ),
    _Variant.sun => _Look(
      fill: ColorTokens.sun,
      ink: ColorTokens.ink,
      lip: size == AppButtonSize.xl ? LipTokens.sunBig : LipTokens.sun,
      label: _label(),
    ),
    _Variant.danger => _Look(
      fill: ColorTokens.danger,
      ink: ColorTokens.ink,
      lip: LipTokens.danger,
      label: size == AppButtonSize.xl
          ? DesignExtras.dangerButtonLabel
          : _label(),
    ),
    _Variant.tertiary => const _Look(
      fill: null,
      ink: ColorTokens.primary,
      lip: null,
      label: DesignExtras.tertiaryLabel,
    ),
  };

  TextStyle _label() => switch (size) {
    AppButtonSize.xl => TypeTokens.buttonXl,
    AppButtonSize.l => TypeTokens.buttonL,
    AppButtonSize.compact => DesignExtras.compactLabel,
  };
}

final class _Look {
  const _Look({
    required this.fill,
    required this.ink,
    required this.lip,
    required this.label,
    this.ring,
  });

  final Color? fill;
  final Color ink;
  final BoxShadow? lip;
  final TextStyle label;
  final Border? ring;
}

/// Three dots that pulse in turn while a button waits; still under reduced
/// motion.
class _LoadingDots extends StatefulWidget {
  const _LoadingDots({required this.color, super.key});

  final Color color;

  @override
  State<_LoadingDots> createState() => _LoadingDotsState();
}

class _LoadingDotsState extends State<_LoadingDots>
    with SingleTickerProviderStateMixin {
  static const _dot = 8.0;
  static const _cycle = Duration(milliseconds: 900);

  late final _pulse = AnimationController(vsync: this, duration: _cycle);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _pulse.stop();
    } else if (!_pulse.isAnimating) {
      _pulse.repeat();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _pulse,
    builder: (context, _) => Row(
      mainAxisSize: MainAxisSize.min,
      spacing: SpaceTokens.s6,
      children: [
        for (var i = 0; i < 3; i++)
          Opacity(
            opacity: _opacity(i),
            child: Container(
              width: _dot,
              height: _dot,
              decoration: BoxDecoration(
                color: widget.color,
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
    ),
  );

  double _opacity(int i) {
    if (!_pulse.isAnimating) return 1;
    final phase = (_pulse.value * 3 - i) % 3;
    return phase < 1 ? 1 : 0.35;
  }
}

/// The fuel a button costs (HANDOFF §9.1 #4): a `sun` pill with «−n» and
/// the fuel icon, never «لتر». [large] sizes it for a 64-high button.
class CostChip extends StatelessWidget {
  const CostChip({required this.amount, this.large = false, super.key});

  /// Preformatted, for example «−١».
  final String amount;
  final bool large;

  static const double _height = 26;
  static const double _icon = 14;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: ColorTokens.sun,
      borderRadius: BorderRadius.circular(RadiusTokens.pill),
    ),
    child: SizedBox(
      height: large ? DesignExtras.costChipHeight : _height,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: SpaceTokens.s8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: SpaceTokens.s2,
          children: [
            Text(
              amount,
              style:
                  (large ? DesignExtras.compactLabel : DesignExtras.chipLabel)
                      .copyWith(color: ColorTokens.ink),
            ),
            const AppIcon('fuel_small', size: _icon),
          ],
        ),
      ),
    ),
  );
}

/// A rewarded-ad offer (HANDOFF §3.1, `Components` box 10). Built for M11:
/// no screen shows it yet (spec FR-029). Not [ready]: the not-ready icon and
/// «الإعلان مش جاهز», disabled.
class RewardedAdButton extends StatelessWidget {
  const RewardedAdButton({
    required this.ready,
    required this.title,
    required this.benefit,
    required this.onTap,
    this.semanticLabel,
    super.key,
  });

  final bool ready;
  final String title;

  /// The benefit line, for example «+١٧٠ بدل ٨٥».
  final String benefit;
  final VoidCallback onTap;
  final String? semanticLabel;

  static const double _icon = 26;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final notReady = l10n.adNotReady;
    final radius = BorderRadius.circular(LayoutTokens.ctaRadius);
    return Pressable(
      onTap: onTap,
      enabled: ready,
      lip: LipTokens.primary,
      borderRadius: radius,
      semanticLabel: ready
          ? (semanticLabel ?? l10n.pairLabel(title, benefit))
          : notReady,
      child: SizedBox(
        width: double.infinity,
        height: DesignExtras.rewardedHeight,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: ColorTokens.primary,
            borderRadius: radius,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: SpaceTokens.s10,
            children: [
              AppIcon(
                ready ? 'ad_play_on_primary' : 'ad_not_ready',
                size: _icon,
                color: ColorTokens.paper,
              ),
              if (ready)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: DesignExtras.rewardedTitle.copyWith(
                        color: ColorTokens.paper,
                      ),
                    ),
                    Text(
                      benefit,
                      style: TypeTokens.label
                          .weight(400)
                          .copyWith(color: ColorTokens.primarySoft),
                    ),
                  ],
                )
              else
                Text(
                  notReady,
                  style: TypeTokens.buttonL.copyWith(color: ColorTokens.paper),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A 44×44 round button with one icon (HANDOFF §3.1): white with a lip on
/// `ground` pages, `ground` without one inside sheets.
class IconCircleButton extends StatelessWidget {
  const IconCircleButton({
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
    this.inSheet = false,
    super.key,
  });

  /// `close`, `back` (pointing right in RTL), `pause`, `edit` or `copy`.
  final String icon;
  final String semanticLabel;
  final VoidCallback? onTap;
  final bool inSheet;

  static const double size = LayoutTokens.touchMin;
  static const double _glyph = 18;

  @override
  Widget build(BuildContext context) => Pressable(
    onTap: onTap,
    lip: inSheet ? null : LipTokens.cardSmall,
    borderRadius: BorderRadius.circular(size / 2),
    semanticLabel: semanticLabel,
    child: Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: inSheet ? ColorTokens.ground : ColorTokens.paper,
        shape: BoxShape.circle,
        border: inSheet
            ? null
            : Border.all(
                color: ColorTokens.track,
                width: 1,
                strokeAlign: BorderSide.strokeAlignInside,
              ),
      ),
      child: AppIcon(icon, size: _glyph, color: ColorTokens.ink),
    ),
  );
}
