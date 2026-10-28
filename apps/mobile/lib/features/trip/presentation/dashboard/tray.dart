// «درج الفكة» (HANDOFF §3.4 `ChangeTray`, `C-Trip` boxes 64–80): eight
// cells in a 4×2 grid, نص، ١، ٥، ١٠ then ٢٠، ٥٠، ١٠٠، ٢٠٠. A cell is a
// white tile on its lip with the coin or note and «×N»; an empty one is
// dashed and faded, and shakes when tapped; while a note waits to be broken,
// the ones that can be ring in `danger`.
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/theme/components/pressable.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/onboarding/domain/tutorial_coach.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';
import 'package:wassal/features/trip/presentation/coach_anchors.dart';
import 'package:wassal/features/trip/presentation/dashboard/dashed_outline.dart';
import 'package:wassal/features/trip/presentation/trip_colors.dart';
import 'package:wassal/features/trip/presentation/trip_scope.dart';
import 'package:wassal/features/trip/presentation/trip_text.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

/// The gap between cells, both ways.
const traySlotGap = SpaceTokens.s6;

class Tray extends StatelessWidget {
  const Tray({this.rowGap = traySlotGap, super.key});

  /// Between its two rows: 4 in the compact dashboard (M07).
  final double rowGap;

  static Key slotKey(int denomination) => ValueKey('trip-tray-$denomination');

  @override
  Widget build(BuildContext context) {
    return TripSelector<List<TraySlotView>>(
      select: (model) => model.view?.tray ?? const [],
      equals: listEquals,
      builder: (context, slots) {
        if (slots.isEmpty) return const SizedBox.shrink();
        final rows = [slots.take(4).toList(), slots.skip(4).toList()];
        final grid = Column(
          children: [
            for (final (i, row) in rows.indexed) ...[
              if (i > 0) SizedBox(height: rowGap),
              Expanded(
                child: Row(
                  children: [
                    for (final (j, slot) in row.indexed) ...[
                      if (j > 0) const SizedBox(width: traySlotGap),
                      Expanded(
                        child: CoachAnchor(
                          target: TrayCellTarget(slot.denomination),
                          child: _TraySlot(slot: slot),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
        return CoachAnchor(target: const TrayTarget(), child: grid);
      },
    );
  }
}

class _TraySlot extends ConsumerWidget {
  const _TraySlot({required this.slot});

  final TraySlotView slot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final numbers = ref.watch(numberFormatterProvider);
    final l10n = AppLocalizations.of(context);
    final controls = TripScope.of(context).controls;
    final d = slot.denomination;
    final empty = slot.count == 0;
    final state = empty
        ? TrayCellState.empty
        : slot.breakable
        ? TrayCellState.breakable
        : TrayCellState.full;
    return Shakeable(
      controlKey: TripControls.trayKey(d),
      child: KeyedSubtree(
        key: Tray.slotKey(d),
        child: TrayCell(
          state: state,
          denomination: d,
          label: l10n.trayLabel(d, numbers),
          count: l10n.tripTimes(numbers.integer(slot.count)),
          semanticLabel: empty
              ? l10n.tripTrayEmptySlot(numbers.piasters(d))
              : l10n.tripTraySlot(
                  d == 100 ? 'pound' : 'other',
                  l10n.trayLabel(d, numbers),
                  numbers.integer(slot.count),
                ),
          // An empty cell still takes the tap: the drawer shakes and says why.
          onTap: () => controls.pick(d),
        ),
      ),
    );
  }
}

/// A drawer cell's look (HANDOFF §3.4 `TrayCell`).
enum TrayCellState {
  full,
  empty,

  /// A note the drawer can break, while it waits for one.
  breakable,

  /// Pushed into its lip; live cells get it from the press itself.
  pressed,
}

/// One drawer cell: the coin or note in its colour, then «×N».
class TrayCell extends StatelessWidget {
  const TrayCell({
    required this.state,
    required this.denomination,
    required this.label,
    required this.count,
    this.semanticLabel,
    this.onTap,
    super.key,
  });

  final TrayCellState state;
  final int denomination;

  /// The coin's or note's own text: «نص», «١», «٥».
  final String label;

  /// «×N».
  final String count;
  final String? semanticLabel;
  final VoidCallback? onTap;

  static const double _radius = RadiusTokens.tray;
  static const _corners = BorderRadius.all(Radius.circular(_radius));

  @override
  Widget build(BuildContext context) {
    final empty = state == TrayCellState.empty;
    final ink = empty ? ColorTokens.dashboardText : ColorTokens.ink;
    final face = SizedBox(
      height: LayoutTokens.touchMin,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: empty ? null : ColorTokens.paper,
          borderRadius: _corners,
          boxShadow: [
            if (state == TrayCellState.breakable) RingTokens.hot.spread,
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: SpaceTokens.s6,
          children: [
            _Glyph(denomination: denomination, label: label, empty: empty),
            Text(
              count,
              maxLines: 1,
              softWrap: false,
              style: DesignExtras.compactLabel.copyWith(color: ink, height: 1),
            ),
          ],
        ),
      ),
    );
    final drawn = switch (state) {
      TrayCellState.empty => CustomPaint(
        painter: const DashedOutline(
          color: ColorTokens.dashboardLine,
          radius: _radius,
        ),
        child: face,
      ),
      TrayCellState.pressed => Transform.translate(
        offset: const Offset(0, LipTokens.trayCellDepth),
        child: face,
      ),
      _ => face,
    };
    return Pressable(
      onTap: onTap,
      haptic: false,
      semanticLabel: semanticLabel,
      lip: empty || state == TrayCellState.pressed ? null : LipTokens.trayCell,
      borderRadius: _corners,
      child: drawn,
    );
  }
}

/// A 26 pt coin or a 34×20 note; an empty cell's is a dashed outline.
class _Glyph extends StatelessWidget {
  const _Glyph({
    required this.denomination,
    required this.label,
    required this.empty,
  });

  final int denomination;
  final String label;
  final bool empty;

  @override
  Widget build(BuildContext context) {
    final coin = TripColors.isCoin(denomination);
    final radius = coin ? 13.0 : DesignExtras.miniNoteRadius;
    final glyph = Container(
      width: coin ? 26 : 34,
      height: coin ? 26 : 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: empty ? null : TripColors.denomination(denomination),
        borderRadius: BorderRadius.all(Radius.circular(radius)),
      ),
      child: Text(
        label,
        maxLines: 1,
        softWrap: false,
        style: TypeTokens.label
            .weight(700)
            .copyWith(
              color: empty ? ColorTokens.dashboardText : ColorTokens.ink,
              height: 1,
            ),
      ),
    );
    if (!empty) return glyph;
    // The cell's own outline is its only painter (the empty-slot check
    // looks for one); the glyph's is drawn in front instead.
    return CustomPaint(
      foregroundPainter: DashedOutline(
        color: ColorTokens.dashboardLine,
        radius: radius,
      ),
      child: glyph,
    );
  }
}
