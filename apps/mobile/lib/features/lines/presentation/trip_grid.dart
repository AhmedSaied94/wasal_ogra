// The trip grid (specs/014-m09-lines-vehicles, contracts/line-details.md
// "The cells", HANDOFF `LineDetails` block 2c): five cells a row from the
// right, each a trip with its stars, its «قصة» chip, «كمّل» on the next
// one, or the locked look.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/theme/components/pills.dart';
import 'package:wassal/core/theme/components/pressable.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/lines/domain/trip_cells.dart';
import 'package:wassal/features/lines/presentation/locked_fill.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

class TripGrid extends StatelessWidget {
  const TripGrid({
    required this.cells,
    required this.onTap,
    this.nextKey,
    super.key,
  });

  /// The cells shown, in trip order.
  final List<TripCell> cells;
  final void Function(TripCell cell) onTap;

  /// Given to the next trip's cell, so the sheet can scroll it into view.
  final GlobalKey? nextKey;

  static const double gap = SpaceTokens.s8;

  /// The «قصة» chip rises above its cell, into the gap over it (HANDOFF:
  /// top −6).
  static const double chipRise = SpaceTokens.s6;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    explicitChildNodes: true,
    label: AppLocalizations.of(context).lineDetailsTripsA11y,
    child: LayoutBuilder(
      builder: (context, box) {
        final width = (box.maxWidth - gap * (cellsPerRow - 1)) / cellsPerRow;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: gap,
          children: [
            for (var start = 0; start < cells.length; start += cellsPerRow)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: gap,
                children: [
                  for (final cell in cells.skip(start).take(cellsPerRow))
                    SizedBox(
                      key: cell.state == CellState.next ? nextKey : null,
                      width: width,
                      child: TripCellView(cell: cell, onTap: onTap),
                    ),
                ],
              ),
          ],
        );
      },
    ),
  );
}

class TripCellView extends ConsumerWidget {
  const TripCellView({required this.cell, required this.onTap, super.key});

  final TripCell cell;
  final void Function(TripCell cell) onTap;

  static Key keyOf(String tripId) => Key('TripCell.$tripId');

  /// ≈65×62 as drawn; text grows it.
  static const double height = 62;
  static const double _stars = 12;
  static const double _lock = 14;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final numbers = ref.watch(numberFormatterProvider);
    final n = numbers.integer(cell.number);
    final radius = BorderRadius.circular(RadiusTokens.m);
    final state = switch (cell.state) {
      CellState.done => l10n.lineDetailsStateDone(cell.stars),
      CellState.next => l10n.lineDetailsStateNext,
      CellState.playable => l10n.lineDetailsStatePlayable,
      CellState.locked => l10n.lineDetailsStateLocked,
    };
    final label = cell.isStory
        ? l10n.lineDetailsCellStoryA11y(n, state)
        : l10n.lineDetailsCellA11y(n, state);
    final primary =
        cell.state == CellState.next || cell.state == CellState.playable;
    // A done cell the rules no longer allow keeps its stars, drawn locked
    // (§9.1 #6) and not as a link (FR-026).
    final inert = cell.state == CellState.done && !cell.playable;
    final decoration = switch (cell.state) {
      CellState.done when inert => lockedFill(radius),
      CellState.done => BoxDecoration(
        color: cell.isStory ? ColorTokens.sunSoft : ColorTokens.ground,
        borderRadius: radius,
      ),
      CellState.next || CellState.playable => BoxDecoration(
        color: ColorTokens.primary,
        borderRadius: radius,
      ),
      CellState.locked => lockedFill(radius),
    };
    final face = Container(
      constraints: const BoxConstraints(minHeight: height),
      padding: const EdgeInsets.symmetric(
        horizontal: SpaceTokens.s2,
        vertical: SpaceTokens.s6,
      ),
      decoration: decoration,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: SpaceTokens.s2,
        children: [
          Text(
            n,
            style: switch (cell.state) {
              CellState.next ||
              CellState.playable => DesignExtras.lineDetailsCellNext.copyWith(
                color: ColorTokens.paper,
              ),
              CellState.locked =>
                DesignExtras.lineDetailsCell
                    .weight(600)
                    .copyWith(color: ColorTokens.ink2),
              CellState.done when inert =>
                DesignExtras.lineDetailsCell.copyWith(color: ColorTokens.ink2),
              CellState.done => DesignExtras.lineDetailsCell.copyWith(
                color: ColorTokens.ink,
              ),
            },
          ),
          switch (cell.state) {
            CellState.done => Stars(earned: cell.stars, size: _stars),
            CellState.next => Text(
              l10n.linesContinue,
              textAlign: TextAlign.center,
              style: DesignExtras.lineDetailsCellLabel.copyWith(
                color: ColorTokens.paper,
              ),
            ),
            CellState.playable => const SizedBox.shrink(),
            CellState.locked => const LockGlyph(size: _lock),
          },
        ],
      ),
    );
    final body = Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: [
        face,
        if (cell.isStory)
          Positioned(
            top: -TripGrid.chipRise,
            child: ExcludeSemantics(
              child: StatusChip.story(label: l10n.lineDetailsStory),
            ),
          ),
        // A done cell the rules refuse is marked locked as well as filled.
        if (inert)
          const PositionedDirectional(
            top: SpaceTokens.s2,
            end: SpaceTokens.s2,
            child: LockGlyph(size: 12),
          ),
      ],
    );
    if (!cell.startable) {
      // Not a link: read, never tapped.
      return Semantics(
        key: keyOf(cell.tripId),
        container: true,
        label: label,
        child: ExcludeSemantics(child: body),
      );
    }
    return Pressable(
      key: keyOf(cell.tripId),
      onTap: () => onTap(cell),
      lip: primary ? LipTokens.primaryS : null,
      pressedOpacity: primary ? null : Pressable.disabledOpacity,
      borderRadius: radius,
      semanticLabel: label,
      selected: cell.state == CellState.next ? true : null,
      child: body,
    );
  }
}
