// The rooms view (specs/015-m10-apartment-story, contracts/apartment.md "The
// rooms view", HANDOFF `AptRooms` and the boards of 2026-10-31): the header
// with the rewards on their way, the room's chapter bar, its tabs, the
// drawing, the grid of pieces and the strip.
import 'dart:async';

import 'package:content_models/content_models.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/economy/economy_providers.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/l10n/number_formatter.dart';
import 'package:wassal/core/progress/application/pending_rewards_provider.dart';
import 'package:wassal/core/progress/domain/story.dart';
import 'package:wassal/core/routing/nav_guard.dart';
import 'package:wassal/core/theme/components/app_icon.dart';
import 'package:wassal/core/theme/components/containers.dart';
import 'package:wassal/core/theme/components/pills.dart';
import 'package:wassal/core/theme/components/pressable.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/apartment/application/apartment_providers.dart';
import 'package:wassal/features/apartment/domain/room_model.dart';
import 'package:wassal/features/apartment/presentation/chapter_bar.dart';
import 'package:wassal/features/apartment/presentation/pending_chip.dart';
import 'package:wassal/features/apartment/presentation/room_scene.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

const double roomsGap = SpaceTokens.s10;

class ApartmentRoomsView extends ConsumerStatefulWidget {
  const ApartmentRoomsView({
    required this.model,
    required this.storyEnd,
    super.key,
  });

  final RoomModel model;
  final bool storyEnd;

  static const gridCellH = 56.0;

  @override
  ConsumerState<ApartmentRoomsView> createState() => _ApartmentRoomsViewState();
}

class _ApartmentRoomsViewState extends ConsumerState<ApartmentRoomsView> {
  /// A tap or a scroll on the view ends سلمى's bubble (research R9).
  void _endBubble() {
    if (ref.read(boughtPieceProvider) != null) {
      ref.read(boughtPieceProvider.notifier).clear();
    }
  }

  /// «اشتريت {piece}» once, politely, when a purchase lands.
  void _announce(BoughtRecord? bought) {
    if (bought == null) return;
    final item = widget.model.pieces
        .map((cell) => cell.item)
        .where((item) => item.itemId == bought.itemId)
        .firstOrNull;
    if (item == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        SemanticsService.sendAnnouncement(
          View.of(context),
          AppLocalizations.of(context).aptBought(item.name.arEg),
          TextDirection.rtl,
        ),
      );
    });
  }

  RoomBought? _boughtHere(BoughtRecord? bought) {
    if (bought == null) return null;
    final item = widget.model.pieces
        .map((cell) => cell.item)
        .where((item) => item.itemId == bought.itemId)
        .firstOrNull;
    if (item == null) return null;
    final variant = item.variants
        .where((v) => v.variantId == bought.variantId)
        .firstOrNull;
    final line = variant?.comment?.arEg ?? item.comment?.arEg;
    if (line == null) return null;
    return (item: item, variantId: bought.variantId, line: line);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final numbers = ref.watch(numberFormatterProvider);
    final model = widget.model;
    ref.listen(boughtPieceProvider, (_, next) => _announce(next));
    final bought = _boughtHere(ref.watch(boughtPieceProvider));
    final scenePending =
        model.complete && model.goalSceneState == SceneState.waiting;
    final children = <Widget>[
      const _Header(),
      const SizedBox(height: roomsGap),
      ChapterBar(
        trailingIsControl: scenePending,
        trailingChild: scenePending
            ? _SceneChip(scene: model.goalScene!, owned: model.total)
            : _RoomBarProgress(owned: model.owned, total: model.total),
        semanticLabel: model.complete
            ? l10n.aptRoomsChapterDoneA11y(
                numbers.integer(model.chapter.order),
                model.chapter.title.arEg,
              )
            : l10n.aptRoomsChapterA11y(
                numbers.integer(model.chapter.order),
                model.chapter.title.arEg,
                numbers.integer(model.owned),
                numbers.integer(model.total),
              ),
        title: _RoomBarTitle(chapter: model.chapter, done: scenePending),
        trailing: l10n.aptGoalAllChapters,
      ),
      const SizedBox(height: roomsGap),
      _TabsRow(model: model),
      const SizedBox(height: roomsGap),
      RoomScene(
        model: model,
        bought: bought,
        onTap: (item) => NavGuard.go(context, '/apartment/item/${item.itemId}'),
      ),
      const SizedBox(height: roomsGap),
      _Grid(model: model),
      const SizedBox(height: roomsGap),
      if (widget.storyEnd)
        _Strip(text: l10n.storyEndLine, icon: 'clock')
      else if (!model.complete && model.goalScene != null)
        _Strip(
          text: l10n.aptRoomsStrip(
            model.room.name.arEg,
            model.goalScene!.title.arEg,
          ),
          icon: 'album',
        ),
    ];
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _endBubble(),
      child: NotificationListener<ScrollStartNotification>(
        onNotification: (_) {
          _endBubble();
          return false;
        },
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            LayoutTokens.gutter,
            MediaQuery.paddingOf(context).top,
            LayoutTokens.gutter,
            SpaceTokens.s12,
          ),
          children: children,
        ),
      ),
    );
  }
}

/// The title, the pending rewards between it and the coins pill, and the
/// pill (`AptRoomsAffordable` 1 to 7).
class _Header extends ConsumerWidget {
  const _Header();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final numbers = ref.watch(numberFormatterProvider);
    final jenehat = ref.watch(economyViewProvider).jenehat;
    final pending = ref.watch(pendingRewardTotalProvider) > 0;
    return SizedBox(
      height: 52,
      child: Row(
        spacing: SpaceTokens.s6,
        children: [
          Expanded(
            child: Text(
              l10n.apartmentTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TypeTokens.displayL,
            ),
          ),
          if (pending) const PendingChip(),
          CurrencyPill(
            kind: CurrencyKind.coin,
            value: numbers.integer(jenehat),
            semanticLabel: l10n.homeA11yCoins(numbers.integer(jenehat)),
          ),
        ],
      ),
    );
  }
}

/// «الفصل ٤ · الصالة» over its tagline; once the room's scene waits, a
/// chevron after the title says the rest of the bar opens the timeline.
class _RoomBarTitle extends ConsumerWidget {
  const _RoomBarTitle({required this.chapter, required this.done});

  final Chapter chapter;
  final bool done;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final numbers = ref.watch(numberFormatterProvider);
    final tagline = chapter.tagline?.arEg;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          spacing: SpaceTokens.s4,
          children: [
            Flexible(
              child: Text(
                l10n.aptGoalChapterBar(
                  numbers.integer(chapter.order),
                  chapter.title.arEg,
                ),
                maxLines: 2,
                style: TypeTokens.displayS.copyWith(color: ColorTokens.paper),
              ),
            ),
            if (done)
              const AppIcon(
                'chevron_back_soft',
                size: 16,
                color: ColorTokens.paper,
              ),
          ],
        ),
        if (tagline != null)
          Text(
            tagline,
            style: TypeTokens.label
                .weight(500)
                .copyWith(color: ColorTokens.primarySoft),
          ),
      ],
    );
  }
}

/// «جهّزت {n} من {total}» over an 80 x 8 bar, at the bar's end.
class _RoomBarProgress extends ConsumerWidget {
  const _RoomBarProgress({required this.owned, required this.total});

  final int owned;
  final int total;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final numbers = ref.watch(numberFormatterProvider);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      spacing: SpaceTokens.s4,
      children: [
        Text(
          l10n.aptRoomsChapterProgress(
            numbers.integer(owned),
            numbers.integer(total),
          ),
          style: TypeTokens.label.copyWith(color: ColorTokens.paper),
        ),
        _Bar(owned: owned, total: total),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.owned, required this.total});

  final int owned;
  final int total;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: DesignExtras.roomBarWidth,
    child: ProgressBar(
      value: total == 0 ? 0 : owned / total,
      color: ProgressColor.sun,
      track: ColorTokens.primaryLip,
      height: 8,
    ),
  );
}

/// The finished room's «شوف المشهد» over the full bar (`AptRoomsDone` 9 to
/// 13): a sun pill, 28 drawn and 44 to hit, its own button inside the bar.
class _SceneChip extends StatelessWidget {
  const _SceneChip({required this.scene, required this.owned});

  final Scene scene;
  final int owned;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final radius = BorderRadius.circular(RadiusTokens.pill);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      spacing: SpaceTokens.s6,
      children: [
        // The pill is 28 in the bar's flow, its hit row 44 around it.
        SizedBox(
          height: DesignExtras.sceneChipHeight,
          child: OverflowBox(
            minHeight: LayoutTokens.touchMin,
            maxHeight: LayoutTokens.touchMin,
            child: Pressable(
              onTap: () => NavGuard.go(
                context,
                '/story/scene/${scene.sceneId}?then=/apartment',
              ),
              borderRadius: radius,
              semanticLabel: l10n.aptWatchScene(scene.title.arEg),
              child: Container(
                height: DesignExtras.sceneChipHeight,
                padding: const EdgeInsets.symmetric(
                  horizontal: SpaceTokens.s12,
                ),
                decoration: BoxDecoration(
                  color: ColorTokens.sun,
                  borderRadius: radius,
                  boxShadow: const [LipTokens.sunS],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: SpaceTokens.s6,
                  children: [
                    Text(
                      l10n.roomDoneCta,
                      style: TypeTokens.caption
                          .weight(700)
                          .copyWith(color: ColorTokens.ink),
                    ),
                    const AppIcon('play', size: 14, color: ColorTokens.ink),
                  ],
                ),
              ),
            ),
          ),
        ),
        _Bar(owned: owned, total: owned),
      ],
    );
  }
}

class _TabsRow extends ConsumerWidget {
  const _TabsRow({required this.model});

  final RoomModel model;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final numbers = ref.watch(numberFormatterProvider);
    final selected = ref.watch(roomTabIdProvider) ?? model.room.roomId;
    final radius = BorderRadius.circular(RadiusTokens.m);
    return SizedBox(
      height: LayoutTokens.touchMin,
      child: Row(
        spacing: SpaceTokens.s8,
        children: [
          Expanded(
            child: Semantics(
              container: true,
              label: l10n.aptRoomsTabsLabel,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: ColorTokens.paper,
                  borderRadius: radius,
                  boxShadow: const [LipTokens.cardSmall],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(SpaceTokens.s4),
                  child: Row(
                    spacing: SpaceTokens.s4,
                    children: [
                      for (final tab in model.tabs)
                        Expanded(
                          flex: tab.roomId == RoomId.bedroom ? 25 : 20,
                          child: _Tab(
                            tab: tab,
                            selected: selected == tab.roomId,
                            onTap: () =>
                                ref.read(roomTabIdProvider.notifier).tab =
                                    tab.roomId,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            width: DesignExtras.requestsButtonWidth,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: Pressable(
                    onTap: () => NavGuard.go(context, '/apartment/requests'),
                    borderRadius: radius,
                    lip: DesignExtras.requestsButtonLip,
                    expand: true,
                    semanticLabel: model.requestCount > 0
                        ? l10n.aptRoomsRequestsA11y(
                            numbers.integer(model.requestCount),
                          )
                        : l10n.aptRoomsRequestsNoneA11y,
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: ColorTokens.sunSoft,
                        borderRadius: radius,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        spacing: SpaceTokens.s4,
                        children: [
                          Text(
                            l10n.aptRoomsRequests,
                            style: TypeTokens.caption
                                .weight(700)
                                .copyWith(color: ColorTokens.ink),
                          ),
                          const AppIcon('requests_list', size: 18),
                        ],
                      ),
                    ),
                  ),
                ),
                if (model.requestCount > 0)
                  PositionedDirectional(
                    top: -6,
                    end: -4,
                    child: ExcludeSemantics(
                      child: CountBadge(
                        text: numbers.integer(model.requestCount),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.tab, required this.selected, required this.onTap});

  final RoomTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final name = switch (tab) {
      SelectableTab(:final room) => room.name.arEg,
      LockedTab(:final roomId) => roomName(l10n, roomId),
    };
    final locked = tab is LockedTab;
    final radius = BorderRadius.circular(RadiusTokens.s);
    // The drawn tab is 36 in the row's 4 padding; a selectable one's hit row
    // is 44 (Pressable), a locked one is inert and draws no more than 36.
    final face = Container(
      height: DesignExtras.roomTabHeight,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected && !locked ? ColorTokens.sun : null,
        borderRadius: radius,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: SpaceTokens.s4,
        children: [
          if (locked) const AppIcon('lock', size: 12),
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TypeTokens.caption
                  .weight(locked ? 600 : 700)
                  .copyWith(
                    color: locked ? ColorTokens.inkMuted : ColorTokens.ink,
                  ),
            ),
          ),
        ],
      ),
    );
    final label = l10n.aptRoomsTabsA11y(name, locked ? 'locked' : 'open');
    if (locked) {
      return Semantics(
        container: true,
        button: true,
        enabled: false,
        label: label,
        child: ExcludeSemantics(child: face),
      );
    }
    return Pressable(
      onTap: onTap,
      expand: true,
      borderRadius: radius,
      semanticLabel: label,
      selected: selected,
      child: face,
    );
  }
}

/// A room the pack may lack, named in ARB (`roomTeaserName`).
String roomName(AppLocalizations l10n, RoomId roomId) => switch (roomId) {
  RoomId.salon => l10n.roomNameSalon,
  RoomId.kitchen => l10n.roomNameKitchen,
  RoomId.bedroom => l10n.roomNameBedroom,
};

class _Grid extends ConsumerWidget {
  const _Grid({required this.model});

  final RoomModel model;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final numbers = ref.watch(numberFormatterProvider);
    return Semantics(
      label: l10n.aptRoomsGridA11y(model.room.name.arEg),
      child: Column(
        spacing: SpaceTokens.s8,
        children: [
          for (var i = 0; i < model.pieces.length; i += 2)
            Row(
              spacing: SpaceTokens.s8,
              children: [
                for (final cell in model.pieces.skip(i).take(2))
                  Expanded(
                    child: _PieceCard(cell: cell, numbers: numbers),
                  ),
                if (i + 1 >= model.pieces.length) const Spacer(),
              ],
            ),
        ],
      ),
    );
  }
}

class _PieceCard extends StatelessWidget {
  const _PieceCard({required this.cell, required this.numbers});

  final PieceCell cell;
  final NumberFormatter numbers;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final name = cell.item.name.arEg;
    final nameText = Text(
      name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: DesignExtras.roomCellName.copyWith(color: ColorTokens.ink),
    );
    TextStyle status(Color color) =>
        TypeTokens.label.weight(700).copyWith(color: color);
    Widget line(Widget end) => Row(
      spacing: SpaceTokens.s6,
      children: [
        Expanded(child: nameText),
        end,
      ],
    );
    final (content, label) = switch (cell) {
      OwnedCell() => (
        line(
          Row(
            mainAxisSize: MainAxisSize.min,
            spacing: SpaceTokens.s4,
            children: [
              Text(l10n.aptRoomsInstalled, style: status(ColorTokens.primary)),
              const AppIcon('check', size: 14, color: ColorTokens.primary),
            ],
          ),
        ),
        null,
      ),
      final NextTargetCell next => (
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: SpaceTokens.s4,
          children: [
            line(
              Text(
                next.affordable
                    ? l10n.aptRoomsAffordable
                    : l10n.aptRoomsShort(numbers.integer(next.shortfall)),
                style: status(
                  next.affordable ? ColorTokens.primary : ColorTokens.dangerInk,
                ),
              ),
            ),
            ProgressBar(
              value: next.progress.fraction,
              color: ProgressColor.gold,
              height: 6,
            ),
          ],
        ),
        next.affordable
            ? l10n.aptRoomsCellAffordableA11y(name, numbers.integer(next.price))
            : l10n.aptRoomsCellShortA11y(name, numbers.integer(next.shortfall)),
      ),
      final MissingCell missing => (
        line(
          Text(
            l10n.aptRoomsPrice(numbers.integer(missing.price)),
            style: TypeTokens.caption
                .weight(700)
                .copyWith(color: ColorTokens.ink),
          ),
        ),
        l10n.aptRoomsChipA11y(name, numbers.integer(missing.price)),
      ),
    };
    final radius = BorderRadius.circular(RadiusTokens.bubble);
    final card = Container(
      constraints: const BoxConstraints(
        minHeight: ApartmentRoomsView.gridCellH,
      ),
      padding: const EdgeInsets.symmetric(horizontal: SpaceTokens.s12),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: ColorTokens.paper, borderRadius: radius),
      child: content,
    );
    if (cell is OwnedCell) return card;
    return Pressable(
      onTap: () => NavGuard.go(context, '/apartment/item/${cell.item.itemId}'),
      borderRadius: radius,
      lip: LipTokens.cardSmall,
      expand: true,
      semanticLabel: label,
      child: card,
    );
  }
}

/// The dark strip under the grid: its icon at the start, then the line
/// (`AptRoomsAffordable` 47, `AptRoomsDone` 37).
class _Strip extends StatelessWidget {
  const _Strip({required this.text, required this.icon});

  final String text;
  final String icon;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: DesignExtras.roomStripHeight),
    padding: const EdgeInsets.symmetric(horizontal: SpaceTokens.s12),
    decoration: BoxDecoration(
      color: ColorTokens.dashboardBg,
      borderRadius: BorderRadius.circular(RadiusTokens.m),
    ),
    child: Row(
      spacing: SpaceTokens.s8,
      children: [
        AppIcon(icon, size: 20, color: ColorTokens.sun),
        Expanded(
          child: Text(
            text,
            style: TypeTokens.caption
                .weight(500)
                .copyWith(color: ColorTokens.paper),
          ),
        ),
      ],
    ),
  );
}
