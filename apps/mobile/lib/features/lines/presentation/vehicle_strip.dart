// The vehicle strip (specs/014-m09-lines-vehicles, contracts/lines.md
// "Layout", HANDOFF `Lines` block 2): one tile a vehicle, from the right,
// each opening its sheet.
import 'package:content_models/content_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/routing/nav_guard.dart';
import 'package:wassal/core/theme/components/app_icon.dart';
import 'package:wassal/core/theme/components/pressable.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/core/economy/domain/wire.dart';
import 'package:wassal/features/lines/domain/vehicle_tiles.dart';
import 'package:wassal/features/lines/presentation/locked_fill.dart';
import 'package:wassal/features/lines/presentation/vehicle_art.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

class VehicleStrip extends StatelessWidget {
  const VehicleStrip({required this.tiles, super.key});

  final List<VehicleTile> tiles;

  static const double height = 96;

  /// Four columns fill the 358 between the gutters.
  static const double tileWidth = 83.5;
  static const double _gap = SpaceTokens.s8;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    explicitChildNodes: true,
    label: AppLocalizations.of(context).linesVehiclesA11y,
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: LayoutTokens.gutter),
      // The tiles' lips and presses stay inside the strip.
      clipBehavior: Clip.none,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: _gap,
        children: [for (final tile in tiles) VehicleTileView(tile: tile)],
      ),
    ),
  );
}

/// One tile: done (a tick), current (`sun`), for sale (the locked look
/// with its price) or not for sale (the locked look).
class VehicleTileView extends ConsumerWidget {
  const VehicleTileView({required this.tile, super.key});

  final VehicleTile tile;

  static Key keyOf(VehicleId vehicle) =>
      Key('VehicleTile.${vehicleWire[vehicle]}');

  static const double _artWidth = 64;
  static const double _artHeight = 40;
  static const double _badge = 20;
  static const double _tick = 14;
  static const double _coin = 12;
  static const double _badgeInset = SpaceTokens.s6;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final numbers = ref.watch(numberFormatterProvider);
    final radius = BorderRadius.circular(RadiusTokens.bubble);
    final state = tile.state;
    final (decoration, lip) = switch (state) {
      TileDone() => (
        BoxDecoration(color: ColorTokens.paper, borderRadius: radius),
        LipTokens.cardSmall,
      ),
      TileCurrent() => (
        BoxDecoration(color: ColorTokens.sun, borderRadius: radius),
        LipTokens.sun,
      ),
      TileForSale() || TileNotForSale() => (lockedFill(radius), null),
    };
    final locked = lip == null;
    final nameStyle =
        (state is TileCurrent
                ? DesignExtras.linesTileCurrent
                : DesignExtras.linesTileName)
            .copyWith(color: locked ? ColorTokens.ink2 : ColorTokens.ink);
    final label = switch (state) {
      TileDone() => l10n.linesTileA11yDone(tile.name),
      TileCurrent() => l10n.linesTileA11yCurrent(tile.name),
      TileForSale(:final priceJenehat) => l10n.linesTileA11yPrice(
        tile.name,
        numbers.integer(priceJenehat),
      ),
      TileNotForSale() => l10n.linesTileA11yNotForSale(tile.name),
    };
    return Pressable(
      key: keyOf(tile.vehicle),
      onTap: () =>
          NavGuard.go(context, '/lines/vehicle/${vehicleWire[tile.vehicle]}'),
      lip: lip,
      borderRadius: radius,
      semanticLabel: label,
      child: Container(
        width: VehicleStrip.tileWidth,
        constraints: const BoxConstraints(minHeight: VehicleStrip.height),
        decoration: decoration,
        padding: const EdgeInsets.symmetric(
          horizontal: SpaceTokens.s4,
          vertical: SpaceTokens.s8,
        ),
        child: Stack(
          alignment: Alignment.topCenter,
          clipBehavior: Clip.none,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              spacing: SpaceTokens.s4,
              children: [
                SizedBox(
                  width: _artWidth,
                  height: _artHeight,
                  child: VehicleArt(vehicle: tile.vehicle),
                ),
                Text(
                  state is TileCurrent
                      ? l10n.linesTileCurrent(tile.shortName)
                      : tile.shortName,
                  textAlign: TextAlign.center,
                  style: nameStyle,
                ),
                if (state case TileForSale(:final priceJenehat))
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: SpaceTokens.s2,
                    children: [
                      const AppIcon('coin', size: _coin),
                      Text(
                        numbers.integer(priceJenehat),
                        style: DesignExtras.linesTileCurrent.copyWith(
                          color: ColorTokens.ink2,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            if (state is TileDone)
              PositionedDirectional(
                top: -SpaceTokens.s8 + _badgeInset,
                end: -SpaceTokens.s4 + _badgeInset,
                child: Container(
                  width: _badge,
                  height: _badge,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: ColorTokens.primary,
                    shape: BoxShape.circle,
                  ),
                  child: const AppIcon(
                    'check',
                    size: _tick,
                    color: ColorTokens.paper,
                  ),
                ),
              ),
            if (locked)
              const PositionedDirectional(
                top: -SpaceTokens.s8 + _badgeInset,
                end: -SpaceTokens.s4 + _badgeInset,
                child: LockGlyph(),
              ),
          ],
        ),
      ),
    );
  }
}
