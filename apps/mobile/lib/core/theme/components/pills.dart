import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/components/app_icon.dart';
import 'package:wassal/core/theme/components/pressable.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';

/// Pills, badges and chips (HANDOFF §3.2, `Components` boxes 28–46). Every
/// number arrives formatted: these widgets never format.

enum CurrencyKind { coin, bonat, fuel }

String _currencyIcon(CurrencyKind kind) => switch (kind) {
  CurrencyKind.coin => 'coin',
  CurrencyKind.bonat => 'bonat',
  CurrencyKind.fuel => 'fuel_small',
};

/// A balance: white, a `ground.lip` lip, the value and its icon. Fuel shows
/// its level over the refill [timer]; an [empty] tank is `danger.soft`.
class CurrencyPill extends StatelessWidget {
  const CurrencyPill({
    required this.kind,
    required this.value,
    this.timer,
    this.timerChild,
    this.empty = false,
    this.height = standardHeight,
    this.onTap,
    this.semanticLabel,
    super.key,
  });

  final CurrencyKind kind;

  /// Preformatted: «١٬٢٤٠», or «٤/٥» for fuel.
  final String value;

  /// Fuel only: the time to the next litre, preformatted.
  final String? timer;

  /// Fuel only: a widget in [timer]'s place, in its style, such as a
  /// countdown that ticks on its own (specs/013-m08-home-result R11).
  final Widget? timerChild;
  final bool empty;
  final double height;

  /// The bonat pill opens the Shop; the fuel pill, the Fuel sheet.
  final VoidCallback? onTap;
  final String? semanticLabel;

  static const double standardHeight = 44;

  /// Some screens draw a 40-high pill (HANDOFF §3.2).
  static const double compactHeight = 40;
  static const double _icon = 24;
  static const double _fuelIcon = 22;

  @override
  Widget build(BuildContext context) {
    final lip = empty
        ? LipTokens.sunSoft.copyWith(color: ColorTokens.dangerSoftLip)
        : LipTokens.cardSmall;
    final radius = BorderRadius.circular(RadiusTokens.pill);
    final fuel = kind == CurrencyKind.fuel;
    final timerStyle = DesignExtras.pillTimer.copyWith(
      color: empty ? ColorTokens.ink : ColorTokens.inkMuted,
    );
    final reading = fuel
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: DesignExtras.pillFuel.copyWith(color: ColorTokens.ink),
              ),
              if (timerChild case final child?)
                DefaultTextStyle.merge(style: timerStyle, child: child)
              else if (timer case final timer?)
                Text(timer, style: timerStyle),
            ],
          )
        : Text(
            value,
            style: DesignExtras.pillNumber.copyWith(color: ColorTokens.ink),
          );
    final face = Container(
      height: height,
      padding: const EdgeInsetsDirectional.only(
        start: SpaceTokens.s6,
        end: SpaceTokens.s12,
      ),
      decoration: BoxDecoration(
        color: empty ? ColorTokens.dangerSoft : ColorTokens.paper,
        borderRadius: radius,
        boxShadow: onTap == null ? [lip] : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: SpaceTokens.s6,
        children: [
          AppIcon(_currencyIcon(kind), size: fuel ? _fuelIcon : _icon),
          reading,
        ],
      ),
    );
    if (onTap == null) {
      return Semantics(
        label: semanticLabel,
        child: ExcludeSemantics(excluding: semanticLabel != null, child: face),
      );
    }
    return Pressable(
      onTap: onTap,
      lip: lip,
      borderRadius: radius,
      semanticLabel: semanticLabel,
      child: face,
    );
  }
}

/// A count such as «٢/٣»: `primary` with white 12/700 text, at least 22×18,
/// with a 44×44 hit area when it can be tapped.
class CountBadge extends StatelessWidget {
  const CountBadge({
    required this.text,
    this.onTap,
    this.semanticLabel,
    super.key,
  });

  final String text;
  final VoidCallback? onTap;
  final String? semanticLabel;

  static const Size minSize = Size(22, 18);

  @override
  Widget build(BuildContext context) {
    final badge = Container(
      constraints: BoxConstraints(
        minWidth: minSize.width,
        minHeight: minSize.height,
      ),
      padding: const EdgeInsets.symmetric(horizontal: SpaceTokens.s6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: ColorTokens.primary,
        borderRadius: BorderRadius.circular(RadiusTokens.pill),
      ),
      child: Text(
        text,
        style: DesignExtras.chipLabel.copyWith(color: ColorTokens.paper),
      ),
    );
    if (onTap == null) {
      return UnconstrainedBox(child: badge);
    }
    return Pressable(onTap: onTap, semanticLabel: semanticLabel, child: badge);
  }
}

/// «Something new here»: 12, `danger`, with the system's one outline, a
/// 2 pt `ink` ring. It sits at the top-end corner of what it marks.
class NewDot extends StatelessWidget {
  const NewDot({this.semanticLabel, super.key});

  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => Semantics(
    label: semanticLabel,
    child: Container(
      width: RingTokens.newDotSize,
      height: RingTokens.newDotSize,
      decoration: BoxDecoration(
        color: RingTokens.newDotFill,
        shape: BoxShape.circle,
        border: Border.all(
          color: RingTokens.newDotRingColor,
          width: RingTokens.newDotRing,
          strokeAlign: BorderSide.strokeAlignInside,
        ),
      ),
    ),
  );
}

enum _ChipKind { new_, story, done, offline }

/// A state label: new «جديد», story «مشوار قصة», done «خلص», offline
/// «محتاج نت». Long labels wrap to two centred lines (HANDOFF §9.1 #10).
class StatusChip extends StatelessWidget {
  const StatusChip.new_({required this.label, super.key})
    : _kind = _ChipKind.new_;

  const StatusChip.story({required this.label, super.key})
    : _kind = _ChipKind.story;

  const StatusChip.done({required this.label, super.key})
    : _kind = _ChipKind.done;

  const StatusChip.offline({required this.label, super.key})
    : _kind = _ChipKind.offline;

  final String label;
  final _ChipKind _kind;

  static const double height = 22;

  @override
  Widget build(BuildContext context) {
    final (fill, ink) = switch (_kind) {
      _ChipKind.new_ => (ColorTokens.danger, ColorTokens.ink),
      _ChipKind.story => (ColorTokens.sun, ColorTokens.ink),
      _ChipKind.done => (ColorTokens.primarySoft, ColorTokens.primary),
      // `Components` box 46 draws it white on `ground`.
      _ChipKind.offline => (ColorTokens.paper, ColorTokens.ink),
    };
    return UnconstrainedBox(
      child: Container(
        constraints: const BoxConstraints(minHeight: height),
        padding: const EdgeInsets.symmetric(horizontal: SpaceTokens.s8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(RadiusTokens.pill),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 2,
          style: DesignExtras.chipLabel.copyWith(color: ink),
        ),
      ),
    );
  }
}

/// A price: the currency icon and the number. Store prices pass the store's
/// own localized string as [value], without an icon ([kind] null).
class PriceTag extends StatelessWidget {
  const PriceTag({required this.value, this.kind, super.key});

  final String value;
  final CurrencyKind? kind;

  static const double _icon = 20;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    spacing: SpaceTokens.s4,
    children: [
      if (kind case final kind?) AppIcon(_currencyIcon(kind), size: _icon),
      Text(
        value,
        style: DesignExtras.pillNumber.copyWith(color: ColorTokens.ink),
      ),
    ],
  );
}

/// Three stars: earned ones `gold` on a `sun.lip` lip, missing ones as
/// outlines.
class Stars extends StatelessWidget {
  const Stars({required this.earned, this.size = 28, super.key})
    : assert(earned >= 0 && earned <= 3);

  final int earned;
  final double size;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    spacing: SpaceTokens.s4,
    children: [
      for (var i = 0; i < 3; i++) Star(earned: i < earned, size: size),
    ],
  );
}

/// One of [Stars]: gold on its lip when earned, else outlined. The result
/// draws its three at their own sizes (specs/013-m08-home-result, `Result`
/// block 4).
class Star extends StatelessWidget {
  const Star({required this.earned, required this.size, super.key});

  final bool earned;
  final double size;

  @override
  Widget build(BuildContext context) => earned
      ? SizedBox.square(
          dimension: size,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Transform.translate(
                offset: LipTokens.sun.offset,
                child: AppIcon('star', size: size, color: ColorTokens.sunLip),
              ),
              AppIcon('star', size: size, color: ColorTokens.gold),
            ],
          ),
        )
      : AppIcon('star_outline', size: size);
}
