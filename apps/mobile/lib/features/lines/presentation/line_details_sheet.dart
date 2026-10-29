// A line's details (specs/014-m09-lines-vehicles, contracts/line-details.md,
// HANDOFF `LineDetails`, `LineDetailsStory`, `LineDetailsDone`,
// `LineDetailsLocked`): the line's name and stars, the trip grid scrolling
// above the pinned «العب المشوار {n}», the hint and the note. A done line
// has the note's first sentence in the button's place; a locked line shows
// what opens it there, with no note.
import 'dart:async';

import 'package:content_models/content_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/routing/nav_guard.dart';
import 'package:wassal/core/theme/components/app_icon.dart';
import 'package:wassal/core/theme/components/buttons.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/home/application/start_next_trip.dart';
import 'package:wassal/features/lines/application/line_details_model.dart';
import 'package:wassal/features/lines/domain/line_standing.dart';
import 'package:wassal/features/lines/domain/trip_cells.dart';
import 'package:wassal/features/lines/presentation/board_sheet.dart';
import 'package:wassal/features/lines/presentation/status_row.dart';
import 'package:wassal/features/lines/presentation/trip_grid.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

class LineDetailsSheet extends ConsumerStatefulWidget {
  const LineDetailsSheet({required this.lineId, super.key});

  final LineId lineId;

  static const closeKey = Key('LineDetailsSheet.close');
  static const playKey = Key('LineDetailsSheet.play');
  static const scrollKey = Key('LineDetailsSheet.scroll');
  static const hintKey = Key('LineDetailsSheet.hint');
  static const reasonKey = Key('LineDetailsSheet.reason');

  /// The board's gutter is 16 and its foot 24; the shared sheet's are 14.
  static const double _sideExtra = SpaceTokens.s2;
  static const double _footExtra = SpaceTokens.s10;

  /// `LineDetails` block 2: the blocks' gap.
  static const double gap = SpaceTokens.s14;

  /// `LineDetails` block 2: the sheet's top.
  static const double top = 124;

  @override
  ConsumerState<LineDetailsSheet> createState() => _LineDetailsSheetState();
}

class _LineDetailsSheetState extends ConsumerState<LineDetailsSheet> {
  bool _leaving = false;
  final _nextKey = GlobalKey(debugLabel: 'LineDetailsSheet.next');

  @override
  void initState() {
    super.initState();
    // The next trip in view on the first frame, when the rows run past the
    // sheet (FR-025): the grid scrolls only as far as its row.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final next = _nextKey.currentContext;
      if (!mounted || next == null) return;
      Scrollable.ensureVisible(
        next,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    });
  }

  /// A line the pack lacks: back to the map, once.
  void _leave() {
    if (_leaving) return;
    _leaving = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) NavGuard.go(context, '/lines');
    });
  }

  void _start(String tripId) => unawaited(
    startNextTrip(context, ref, tripId: tripId, from: StartFrom.lines),
  );

  @override
  Widget build(BuildContext context) {
    final model = ref.watch(lineDetailsModelProvider(widget.lineId));
    if (model == null) {
      _leave();
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final numbers = ref.watch(numberFormatterProvider);
    final standing = model.standing;
    final state = standing.state;
    final shown = model.cells
        .take(model.range.rows * cellsPerRow)
        .toList(growable: false);
    final reason = switch (model.reason) {
      (reason: NeedsVehicle(), :final name) => l10n.linesNeedsVehicle(name),
      (reason: AfterLine(), :final name) => l10n.linesAfterLine(name),
      _ => null,
    };
    return BoardSheet(
      top: LineDetailsSheet.top,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          LineDetailsSheet._sideExtra,
          0,
          LineDetailsSheet._sideExtra,
          LineDetailsSheet._footExtra,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(standing: standing),
            const SizedBox(height: LineDetailsSheet.gap),
            Expanded(
              child: SingleChildScrollView(
                key: LineDetailsSheet.scrollKey,
                // Room for a story chip on the first row, which rises above
                // its cell (`LineDetailsStory`: the list's 6 on top).
                padding: EdgeInsets.only(
                  top: shown.take(cellsPerRow).any((c) => c.isStory)
                      ? TripGrid.chipRise
                      : 0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: LineDetailsSheet.gap,
                  children: [
                    TripGrid(
                      cells: shown,
                      nextKey: _nextKey,
                      onTap: (cell) => _start(cell.tripId),
                    ),
                    if (model.range.hidden case (final from, final to))
                      Text(
                        key: LineDetailsSheet.hintKey,
                        l10n.lineDetailsHint(
                          numbers.integer(from),
                          numbers.integer(to),
                        ),
                        textAlign: TextAlign.center,
                        style: TypeTokens.label
                            .weight(500)
                            .copyWith(color: ColorTokens.inkMuted),
                      ),
                    if (state is LineCurrent) const _Note(done: false),
                  ],
                ),
              ),
            ),
            switch (state) {
              LineCurrent(:final next) => Padding(
                padding: const EdgeInsets.only(top: LineDetailsSheet.gap),
                child: AppButton.primary(
                  key: LineDetailsSheet.playKey,
                  label: l10n.lineDetailsPlay(numbers.integer(next.number)),
                  labelStyle: DesignExtras.lineDetailsCta,
                  onTap: () => _start(next.tripId),
                ),
              ),
              LineDone() => const Padding(
                padding: EdgeInsets.only(top: LineDetailsSheet.gap),
                child: _Note(done: true),
              ),
              LineLocked() when reason != null => Padding(
                padding: const EdgeInsets.only(top: LineDetailsSheet.gap),
                child: _Reason(reason: reason),
              ),
              _ => const SizedBox.shrink(),
            },
          ],
        ),
      ),
    );
  }
}

/// The line's name over its stars and trips done, and ✕ (`LineDetails`
/// block 2b).
class _Header extends ConsumerWidget {
  const _Header({required this.standing});

  final LineStanding standing;

  static const double _top = SpaceTokens.s14;
  static const double _star = 16;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final numbers = ref.watch(numberFormatterProvider);
    final s = standing;
    return Padding(
      padding: const EdgeInsets.only(top: _top),
      child: Row(
        spacing: SpaceTokens.s10,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: SpaceTokens.s2,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    s.name,
                    style: DesignExtras.lineDetailsTitle.copyWith(
                      color: ColorTokens.ink,
                    ),
                  ),
                ),
                Row(
                  spacing: SpaceTokens.s4,
                  children: [
                    const AppIcon('star', size: _star, color: ColorTokens.gold),
                    Flexible(
                      child: Text(
                        l10n.lineDetailsSummary(
                          numbers.integer(s.starsEarned),
                          s.starsMax,
                          numbers.integer(s.starsMax),
                          s.doneCount,
                          numbers.integer(s.doneCount),
                        ),
                        style: DesignExtras.lineDetailsSummary.copyWith(
                          color: ColorTokens.inkMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconCircleButton(
            key: LineDetailsSheet.closeKey,
            icon: 'close',
            semanticLabel: l10n.closeLabel,
            inSheet: true,
            onTap: () => unawaited(Navigator.of(context).maybePop()),
          ),
        ],
      ),
    );
  }
}

/// What opens a locked line, in the button's place (`LineDetailsLocked`
/// box 75): read, never tapped.
class _Reason extends StatelessWidget {
  const _Reason({required this.reason});

  final String reason;

  @override
  Widget build(BuildContext context) => Semantics(
    key: LineDetailsSheet.reasonKey,
    container: true,
    label: AppLocalizations.of(context).lineDetailsLockedA11y(reason),
    child: ExcludeSemantics(child: StatusRow.locked(text: reason)),
  );
}

/// The note (`LineDetails` block 2e): both sentences under a current
/// line's grid, or the first only, in the button's place, for a done line,
/// which has nothing left to open (`LineDetailsDone`).
class _Note extends StatelessWidget {
  const _Note({required this.done});

  final bool done;

  static const double icon = 22;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SpaceTokens.s12,
        vertical: SpaceTokens.s10,
      ),
      decoration: BoxDecoration(
        color: ColorTokens.ground,
        borderRadius: BorderRadius.circular(RadiusTokens.bubble),
      ),
      child: Row(
        spacing: SpaceTokens.s10,
        children: [
          const AppIcon('info_filled', size: icon, color: ColorTokens.primary),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: l10n.lineDetailsNote1),
                  if (!done) ...[
                    const TextSpan(text: ' '),
                    TextSpan(text: l10n.lineDetailsNote2),
                  ],
                ],
              ),
              style: DesignExtras.lineDetailsNote.copyWith(
                color: ColorTokens.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
