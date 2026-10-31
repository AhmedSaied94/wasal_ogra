// The timeline (specs/015-m10-apartment-story, contracts/scene-viewer.md "The
// timeline", research R13), built to the `Chapters` artboard: the seven
// chapters down a rail, the done ones to replay, the current one with its
// goal, the rest locked.
import 'package:content_models/content_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/art/panel_art.dart';
import 'package:wassal/core/content/content_providers.dart';
import 'package:wassal/core/economy/domain/wire.dart';
import 'package:wassal/core/economy/economy_providers.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/l10n/number_formatter.dart';
import 'package:wassal/core/progress/application/player_progress_provider.dart';
import 'package:wassal/core/routing/nav_guard.dart';
import 'package:wassal/core/theme/components/app_icon.dart';
import 'package:wassal/core/theme/components/containers.dart';
import 'package:wassal/core/theme/components/pills.dart';
import 'package:wassal/core/theme/components/pressable.dart';
import 'package:wassal/core/theme/components/system_bars.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/apartment/application/apartment_providers.dart';
import 'package:wassal/features/apartment/domain/chapter_rows.dart';
import 'package:wassal/features/lines/presentation/locked_fill.dart';
import 'package:wassal/features/story/domain/panel_ref.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

class ChaptersPage extends ConsumerStatefulWidget {
  const ChaptersPage({super.key});

  /// The header's album pill.
  static const albumKey = Key('ChaptersPage.album');

  static Key rowKey(ChapterId id) => ValueKey('ChaptersPage.row.${id.name}');

  static Key watchKey(ChapterId id) =>
      ValueKey('ChaptersPage.watch.${id.name}');

  /// The rail's stretch beside row [index], and its fill.
  static Key railTrackKey(int index) => ValueKey('ChaptersPage.track.$index');

  static Key railFillKey(int index) => ValueKey('ChaptersPage.fill.$index');

  @override
  ConsumerState<ChaptersPage> createState() => _ChaptersPageState();
}

class _ChaptersPageState extends ConsumerState<ChaptersPage> {
  /// Where the rail's fill starts: nothing on the first entry after the
  /// current chapter changed, else where it will stay.
  double? _from;

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/apartment');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final rows = chapterRows(
      ref.watch(contentSourceProvider),
      ref.watch(playerProgressProvider),
      jenehat: ref.watch(economyViewProvider.select((view) => view.jenehat)),
    );
    final reach = _railReach(rows);
    final target = (reach + 1).toDouble();
    // Read now, stored after the frame: a provider can't change while the
    // tree builds.
    _from ??= ref.read(chaptersRailSeenProvider) == reach ? target : 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(chaptersRailSeenProvider.notifier).take(reach);
    });
    final reduced = MediaQuery.disableAnimationsOf(context);
    return SystemBars(
      bottom: ColorTokens.ground,
      child: Scaffold(
        backgroundColor: ColorTokens.ground,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ScreenHeader(
              title: l10n.chaptersTitle,
              fitTitle: true,
              onBack: _back,
              trailing: [
                _AlbumPill(
                  key: ChaptersPage.albumKey,
                  label: l10n.chaptersAlbum,
                  onTap: () => NavGuard.push(context, '/story/album'),
                ),
              ],
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  LayoutTokens.gutter,
                  SpaceTokens.s14,
                  LayoutTokens.gutter,
                  SpaceTokens.s24,
                ),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: _from, end: target),
                  duration: reduced ? Duration.zero : MotionTokens.sheetIn,
                  curve: MotionTokens.sheetInCurve,
                  builder: (context, shown, _) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: _gap,
                    children: [
                      for (final (i, row) in rows.indexed)
                        _RowShell(
                          index: i,
                          last: i == rows.length - 1,
                          // The fill's share of this row's stretch.
                          fill: (shown - i).clamp(0.0, 1.0),
                          toNode: row is CurrentRow,
                          node: _Node(row: row),
                          card: _Card(row: row, onWatch: _watch),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _watch(ChapterId id) =>
      NavGuard.push(context, '/story/${chapterWire[id]}');

  /// The last row the rail's fill reaches: the current one, or the last at
  /// the story's end; -1 with nothing done.
  static int _railReach(List<ChapterRow> rows) {
    final current = rows.indexWhere((row) => row is CurrentRow);
    if (current >= 0) return current;
    return rows.any((row) => row is DoneRow) ? rows.length - 1 : -1;
  }

  static const double _gap = SpaceTokens.s10;
}

/// `Chapters` block 1: «ألبوم المشاهد», a 44-high `paper` pill with its lip.
class _AlbumPill extends StatelessWidget {
  const _AlbumPill({required this.label, required this.onTap, super.key});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(RadiusTokens.pill);
    return Pressable(
      onTap: onTap,
      lip: LipTokens.cardSmall,
      borderRadius: radius,
      semanticLabel: label,
      child: Container(
        height: LayoutTokens.touchMin,
        padding: const EdgeInsets.symmetric(horizontal: SpaceTokens.s14),
        decoration: BoxDecoration(
          color: ColorTokens.paper,
          borderRadius: radius,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: SpaceTokens.s6,
          children: [
            Text(
              label,
              style: DesignExtras.chapterAction.copyWith(
                color: ColorTokens.ink,
              ),
            ),
            const AppIcon('album', size: 18, color: ColorTokens.sun),
          ],
        ),
      ),
    );
  }
}

/// One row with its piece of the rail and its node, beside the card.
class _RowShell extends StatelessWidget {
  const _RowShell({
    required this.index,
    required this.last,
    required this.fill,
    required this.toNode,
    required this.node,
    required this.card,
  });

  final int index;
  final bool last;

  /// 0 to 1: how much of this row's stretch of the rail is filled.
  final double fill;

  /// The fill ends past the node's centre, not at the stretch's end.
  final bool toNode;
  final _Node node;
  final Widget card;

  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    children: [
      Padding(
        padding: const EdgeInsetsDirectional.only(
          start: DesignExtras.chapterCardInset,
        ),
        child: card,
      ),
      Positioned.fill(
        child: _RailStretch(
          index: index,
          first: index == 0,
          last: last,
          fill: fill,
          toNode: toNode,
        ),
      ),
      PositionedDirectional(
        top: 0,
        bottom: 0,
        start: DesignExtras.chapterRailCentre - node.span / 2,
        width: node.span,
        child: Center(child: node),
      ),
    ],
  );
}

/// The rail beside one row: the track from this row's top to the next
/// row's (the first starts above its node, the last ends below it), and the
/// fill over it from the top.
class _RailStretch extends StatelessWidget {
  const _RailStretch({
    required this.index,
    required this.first,
    required this.last,
    required this.fill,
    required this.toNode,
  });

  final int index;
  final bool first;
  final bool last;
  final double fill;
  final bool toNode;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(DesignExtras.chapterRailRadius);
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        final top = first ? height / 2 - DesignExtras.chapterRailHead : 0.0;
        final bottom = last
            ? height / 2 + DesignExtras.chapterRailTail
            : height + _ChaptersPageState._gap;
        final length = bottom - top;
        final extent = toNode
            ? height / 2 + DesignExtras.chapterRailPast - top
            : length;
        return ExcludeSemantics(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              PositionedDirectional(
                start:
                    DesignExtras.chapterRailCentre -
                    DesignExtras.chapterRailWidth / 2,
                width: DesignExtras.chapterRailWidth,
                top: top,
                height: length,
                child: DecoratedBox(
                  key: ChaptersPage.railTrackKey(index),
                  decoration: BoxDecoration(
                    color: ColorTokens.groundLip,
                    borderRadius: radius,
                  ),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                      key: ChaptersPage.railFillKey(index),
                      width: DesignExtras.chapterRailWidth,
                      height: extent * fill,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: ColorTokens.primary,
                          borderRadius: radius,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The node on the rail at a row's centre: a check when done, the sun with
/// its ring when current, an empty ring when locked.
class _Node extends StatelessWidget {
  const _Node({required this.row});

  final ChapterRow row;

  /// The room the node and its ring take beside the rail.
  double get span => switch (row) {
    CurrentRow() =>
      DesignExtras.chapterNodeCurrent + 2 * DesignExtras.chapterNodeRing,
    DoneRow() || LockedRow() => DesignExtras.chapterNode,
  };

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: switch (row) {
      DoneRow() => const _Disc(
        size: DesignExtras.chapterNode,
        color: ColorTokens.primary,
        child: AppIcon(
          'check',
          size: DesignExtras.chapterNodeCheck,
          color: ColorTokens.paper,
        ),
      ),
      CurrentRow() => const _Disc(
        size:
            DesignExtras.chapterNodeCurrent + 2 * DesignExtras.chapterNodeRing,
        color: ColorTokens.primarySoft,
        child: _Disc(
          size: DesignExtras.chapterNodeCurrent,
          color: ColorTokens.sun,
        ),
      ),
      LockedRow() => const _Disc(
        size: DesignExtras.chapterNode,
        color: ColorTokens.ground,
        ring: ColorTokens.groundLip,
      ),
    },
  );
}

class _Disc extends StatelessWidget {
  const _Disc({required this.size, required this.color, this.ring, this.child});

  final double size;
  final Color color;

  /// A 3 pt ring inside, for the empty node.
  final Color? ring;
  final Widget? child;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: ring == null
            ? null
            : Border.all(
                color: ring!,
                width: SpaceTokens.s4 - 1,
                strokeAlign: BorderSide.strokeAlignInside,
              ),
      ),
      child: Center(child: child),
    ),
  );
}

class _Card extends ConsumerWidget {
  const _Card({required this.row, required this.onWatch});

  final ChapterRow row;
  final void Function(ChapterId id) onWatch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final numbers = ref.watch(numberFormatterProvider);
    final number = numbers.integer(row.number);
    final name =
        row.name ?? l10n.chapterTeaserName(chapterWire[row.chapterId]!);
    return switch (row) {
      final DoneRow done => _DoneCard(
        row: done,
        number: l10n.chaptersNumber(number),
        name: name,
        sentence: l10n.chaptersRowA11y('done', number, name, ''),
        watchLabel: l10n.chaptersWatchScene,
        watchA11y: done.sceneTitle == null
            ? l10n.chaptersWatchSceneA11y(number)
            : l10n.aptWatchScene(done.sceneTitle!),
        onWatch: () => onWatch(done.chapterId),
      ),
      final CurrentRow current => _current(
        l10n,
        numbers,
        current,
        number,
        name,
      ),
      final LockedRow locked => _LockedCard(
        row: locked,
        number: l10n.chaptersNumber(number),
        name: name,
        sentence: l10n.chaptersRowA11y('locked', number, name, ''),
      ),
    };
  }
}

Widget _current(
  AppLocalizations l10n,
  NumberFormatter numbers,
  CurrentRow row,
  String number,
  String name,
) {
  final text = _goalText(l10n, numbers, row.goal);
  // A goal that is not a room says what its character says of it (the
  // draft's `goal_line`), not its own name again.
  final goal = row.goal is RoomGoal || row.line == null
      ? text
      : (chip: text.chip, description: row.line);
  return _CurrentCard(
    row: row,
    label: l10n.chaptersCurrent(number),
    name: name,
    goal: goal,
    sentence: l10n.chaptersRowA11y('current', number, name, goal.chip ?? ''),
  );
}

/// The current chapter's chip and description.
typedef _GoalText = ({String? chip, String? description});

_GoalText _goalText(
  AppLocalizations l10n,
  NumberFormatter numbers,
  CurrentGoal? goal,
) => switch (goal) {
  RoomGoal(:final owned, :final total, :final itemNames, :final sceneTitle) => (
    chip: l10n.chaptersItemsChip(
      numbers.integer(owned),
      numbers.integer(total),
    ),
    description: () {
      final items = itemNames.join(l10n.chaptersItemSeparator);
      return sceneTitle == null
          ? items
          : l10n.chaptersCurrentDesc(items, sceneTitle);
    }(),
  ),
  AmountGoal(:final title, :final have, :final of) => (
    chip: l10n.chaptersAmountChip(numbers.integer(have), numbers.integer(of)),
    description: title,
  ),
  CountGoal(:final title, :final done, :final of) => (
    chip: l10n.chaptersCountChip(numbers.integer(done), numbers.integer(of)),
    description: title,
  ),
  null => (chip: null, description: null),
};

/// `Chapters` 3a: a `paper` card, the scene's thumbnail at the start, the
/// number over the name, and «شوف المشهد» at the end.
class _DoneCard extends StatelessWidget {
  const _DoneCard({
    required this.row,
    required this.number,
    required this.name,
    required this.sentence,
    required this.watchLabel,
    required this.watchA11y,
    required this.onWatch,
  });

  final DoneRow row;
  final String number;
  final String name;
  final String sentence;
  final String watchLabel;

  /// What a screen reader says: the three buttons name their chapter.
  final String watchA11y;
  final VoidCallback onWatch;

  @override
  Widget build(BuildContext context) => Semantics(
    key: ChaptersPage.rowKey(row.chapterId),
    container: true,
    label: sentence,
    child: AppCard(
      radius: RadiusTokens.l,
      lip: LipTokens.cardSmall,
      padding: const EdgeInsetsDirectional.only(
        start: SpaceTokens.s10,
        end: SpaceTokens.s12,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: DesignExtras.chapterRowDone,
        ),
        child: Row(
          spacing: SpaceTokens.s10,
          children: [
            if (row.thumb case final thumb?) _Thumb(thumb: thumb),
            Expanded(
              child: ExcludeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      number,
                      style: DesignExtras.chapterNumber.copyWith(
                        color: ColorTokens.inkMuted,
                      ),
                    ),
                    Text(
                      name,
                      style: DesignExtras.chapterName.copyWith(
                        color: ColorTokens.ink,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (row.hasScenes)
              Pressable(
                key: ChaptersPage.watchKey(row.chapterId),
                onTap: onWatch,
                pressedOpacity: 0.7,
                semanticLabel: watchA11y,
                child: Container(
                  height: LayoutTokens.touchMin,
                  padding: const EdgeInsets.symmetric(
                    horizontal: SpaceTokens.s12,
                  ),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: ColorTokens.ground,
                    borderRadius: BorderRadius.circular(RadiusTokens.tray),
                  ),
                  child: Text(
                    watchLabel,
                    style: DesignExtras.chapterAction.copyWith(
                      color: ColorTokens.primary,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

/// `Chapters` 3a: the first panel of the scene, 70×56 on its own ground.
class _Thumb extends StatelessWidget {
  const _Thumb({required this.thumb});

  final PanelRef thumb;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: ClipRRect(
      borderRadius: BorderRadius.circular(RadiusTokens.tray),
      child: SizedBox(
        width: DesignExtras.chapterThumbWidth,
        height: DesignExtras.chapterThumbHeight,
        child: ColoredBox(
          color: PanelArt.groundFor(thumb.art),
          child: PanelArt(slug: thumb.art, speakers: thumb.speakers),
        ),
      ),
    ),
  );
}

/// `Chapters` 3b: the `primary` card of the chapter the player is in. Not
/// tappable.
class _CurrentCard extends StatelessWidget {
  const _CurrentCard({
    required this.row,
    required this.label,
    required this.name,
    required this.goal,
    required this.sentence,
  });

  final CurrentRow row;
  final String label;
  final String name;
  final _GoalText goal;
  final String sentence;

  @override
  Widget build(BuildContext context) => Semantics(
    key: ChaptersPage.rowKey(row.chapterId),
    container: true,
    label: sentence,
    child: ExcludeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: ColorTokens.primary,
          borderRadius: BorderRadius.circular(RadiusTokens.card),
          boxShadow: const [LipTokens.primaryM],
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: DesignExtras.chapterRowCurrent,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: SpaceTokens.s14,
              vertical: SpaceTokens.s8,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              spacing: SpaceTokens.s2,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: DesignExtras.chapterNumber.copyWith(
                          color: ColorTokens.primarySoft,
                        ),
                      ),
                    ),
                    if (goal.chip case final chip?)
                      StatusChip.story(label: chip),
                  ],
                ),
                Text(
                  name,
                  style: DesignExtras.chapterCurrentName.copyWith(
                    color: ColorTokens.paper,
                  ),
                ),
                if (goal.description case final description?)
                  Text(
                    description,
                    style: TypeTokens.caption.copyWith(
                      color: ColorTokens.primarySoft,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// `Chapters` 3c: a chapter not reached, in the locked look, its lock at
/// the end.
class _LockedCard extends StatelessWidget {
  const _LockedCard({
    required this.row,
    required this.number,
    required this.name,
    required this.sentence,
  });

  final LockedRow row;
  final String number;
  final String name;
  final String sentence;

  @override
  Widget build(BuildContext context) => Semantics(
    key: ChaptersPage.rowKey(row.chapterId),
    container: true,
    label: sentence,
    child: ExcludeSemantics(
      child: DecoratedBox(
        decoration: lockedFill(BorderRadius.circular(RadiusTokens.bubble)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: DesignExtras.chapterRowLocked,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: SpaceTokens.s14,
              vertical: SpaceTokens.s8,
            ),
            child: Row(
              spacing: SpaceTokens.s10,
              children: [
                Text(
                  number,
                  style: DesignExtras.chapterNumber.copyWith(
                    color: ColorTokens.ink2,
                  ),
                ),
                Expanded(
                  child: Text(
                    name,
                    style: DesignExtras.chapterLockedName.copyWith(
                      color: ColorTokens.ink2,
                    ),
                  ),
                ),
                const LockGlyph(size: 18),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
