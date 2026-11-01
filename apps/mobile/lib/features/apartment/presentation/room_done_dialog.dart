// RoomDone (specs/015-m10-apartment-story, contracts/apartment.md
// "RoomDone", research R6, R7, and the board `RoomDonePending` of 2026-10-31):
// the room finished, the reward on its way, and the scene it opens.
import 'dart:async';

import 'package:content_models/content_models.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/content/content_providers.dart';
import 'package:wassal/core/content/domain/content_source.dart';
import 'package:wassal/core/content/domain/story_characters.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/progress/application/pending_rewards_provider.dart';
import 'package:wassal/core/progress/domain/rewards.dart';
import 'package:wassal/core/theme/components/app_icon.dart';
import 'package:wassal/core/theme/components/buttons.dart';
import 'package:wassal/core/theme/components/characters.dart';
import 'package:wassal/core/theme/components/overlays.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/apartment/domain/room_model.dart';
import 'package:wassal/features/apartment/presentation/room_scene.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

/// Pops `true` for «شوف المشهد» and `false` for «بعدين»: the piece sheet
/// that opened it goes on from there (it is the page the scene replaces).
class RoomDoneDialog extends ConsumerStatefulWidget {
  const RoomDoneDialog({
    required this.model,
    required this.chapterCompleted,
    super.key,
  });

  final RoomModel model;

  /// This purchase also completed the room's chapter (spec FR-023).
  final bool chapterCompleted;

  static const ctaKey = Key('RoomDone.cta');
  static const laterKey = Key('RoomDone.later');

  /// The drawing's size, the card's least height and the CTA's height, as
  /// drawn (`RoomDonePending` 9, 17, 22).
  static const Size artSize = Size(260, 130);
  static const double quoteHeight = 81.8;
  static const double ctaHeight = 60;
  static const double _avatar = 46;

  @override
  ConsumerState<RoomDoneDialog> createState() => _RoomDoneDialogState();
}

class _RoomDoneDialogState extends ConsumerState<RoomDoneDialog> {
  @override
  void initState() {
    super.initState();
    // Said once, politely, when the dialog opens (board `RoomDonePending` 7).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        SemanticsService.sendAnnouncement(
          View.of(context),
          _announcement(context),
          Directionality.of(context),
        ),
      );
    });
  }

  int _reward(ContentSource content) =>
      widget.model.room.completionBonat +
      (widget.chapterCompleted
          ? content.chapter(widget.model.chapter.chapterId)?.completionBonat ??
                0
          : 0);

  String _announcement(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final numbers = ref.read(numberFormatterProvider);
    return l10n.roomDoneA11y(
      widget.model.room.name.arEg,
      numbers.integer(_reward(ref.read(contentSourceProvider))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final numbers = ref.watch(numberFormatterProvider);
    final model = widget.model;
    final reward = _reward(ref.watch(contentSourceProvider));
    final pending = ref
        .watch(pendingRewardsProvider)
        .any(
          (r) =>
              r.source == RoomReward(model.room.roomId) ||
              r.source == ChapterReward(model.chapter.chapterId),
        );
    final scene = model.goalScene;
    return AppDialog(
      // The board's 20 above the drawing, its 18 on the other sides.
      padding: const EdgeInsets.fromLTRB(
        DesignExtras.dialogPadding,
        DesignExtras.dialogPadding + SpaceTokens.s2,
        DesignExtras.dialogPadding,
        DesignExtras.dialogPadding,
      ),
      semanticLabel: l10n.roomDoneTitle(model.room.name.arEg),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: SpaceTokens.s12,
          children: [
            Center(
              child: ExcludeSemantics(
                child: SizedBox.fromSize(
                  size: RoomDoneDialog.artSize,
                  child: RoomScene(model: model),
                ),
              ),
            ),
            Center(
              child: _ChapterChip(
                label: l10n.roomDoneChip(
                  numbers.integer(model.chapter.order),
                  numbers.integer(model.owned),
                  numbers.integer(model.total),
                ),
              ),
            ),
            ConstrainedBox(
              // 52 as drawn: Marhey 30 on the browser's own line height.
              constraints: const BoxConstraints(minHeight: 52),
              child: Center(
                child: Text(
                  l10n.roomDoneTitle(model.room.name.arEg),
                  textAlign: TextAlign.center,
                  style: DesignExtras.roomDoneTitle,
                ),
              ),
            ),
            Center(
              child: _RewardPill(
                label: l10n.roomDoneReward(numbers.integer(reward)),
                pending: pending ? l10n.roomDonePending : null,
              ),
            ),
            if (model.room.doneLine case final line?) _Quote(line: line.arEg),
            if (scene != null)
              AppButton.primary(
                key: RoomDoneDialog.ctaKey,
                label: l10n.roomDoneCta,
                semanticLabel: l10n.aptWatchScene(scene.title.arEg),
                trailing: const AppIcon(
                  'play',
                  size: 22,
                  color: ColorTokens.paper,
                ),
                labelStyle: TypeTokens.displayM,
                height: RoomDoneDialog.ctaHeight,
                radius: LayoutTokens.ctaRadius,
                onTap: () => Navigator.of(context).pop(true),
              ),
            Center(
              child: AppButton.tertiary(
                key: RoomDoneDialog.laterKey,
                label: l10n.roomDoneLater,
                labelStyle: DesignExtras.piecePriceHave,
                height: LayoutTokens.touchMin,
                onTap: () => Navigator.of(context).pop(false),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// «الفصل ٤ · ٤ من ٤ قطع», a `primary.soft` pill (`RoomDonePending` 10).
class _ChapterChip extends StatelessWidget {
  const _ChapterChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: SpaceTokens.s12,
      vertical: SpaceTokens.s2,
    ),
    decoration: BoxDecoration(
      color: ColorTokens.primarySoft,
      borderRadius: BorderRadius.circular(RadiusTokens.pill),
    ),
    child: Text(
      label,
      style: TypeTokens.caption
          .weight(700)
          .copyWith(color: ColorTokens.primary),
    ),
  );
}

/// «+٤٥ بون مكافأة», and while it is only on its way a second line with a
/// clock mark, «في الطريق» (`RoomDonePending` 12 to 16). A status, no button.
class _RewardPill extends StatelessWidget {
  const _RewardPill({required this.label, required this.pending});

  final String label;
  final String? pending;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: SpaceTokens.s12,
      vertical: SpaceTokens.s6,
    ),
    decoration: BoxDecoration(
      color: ColorTokens.sunSoft,
      borderRadius: BorderRadius.circular(RadiusTokens.pill),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      spacing: SpaceTokens.s8,
      children: [
        const AppIcon('bonat', size: 24),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TypeTokens.bubble.copyWith(
                color: ColorTokens.ink,
                height: 1.2,
              ),
            ),
            if (pending case final text?)
              Row(
                mainAxisSize: MainAxisSize.min,
                spacing: SpaceTokens.s4,
                children: [
                  const AppIcon('clock', size: 14, color: ColorTokens.inkMuted),
                  Text(
                    text,
                    style: TypeTokens.label.copyWith(
                      color: ColorTokens.inkMuted,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    ),
  );
}

/// سلمى's line over her name, on `ground` (`RoomDonePending` 17 to 21).
class _Quote extends StatelessWidget {
  const _Quote({required this.line});

  final String line;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: RoomDoneDialog.quoteHeight),
    padding: const EdgeInsets.all(SpaceTokens.s12),
    decoration: BoxDecoration(
      color: ColorTokens.ground,
      borderRadius: BorderRadius.circular(RadiusTokens.l),
    ),
    child: Row(
      spacing: SpaceTokens.s12,
      children: [
        ClipOval(
          child: SizedBox.square(
            dimension: RoomDoneDialog._avatar,
            child: FittedBox(
              fit: BoxFit.cover,
              child: CharacterAvatar(storyCharacterArt(StoryCharacter.salma)),
            ),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                AppLocalizations.of(context).aptBoughtBubble(line),
                style: DesignExtras.roomDoneQuote.copyWith(
                  color: ColorTokens.ink,
                ),
              ),
              Text(
                AppLocalizations.of(context).sceneSpeaker('salma'),
                style: TypeTokens.label.copyWith(color: ColorTokens.inkMuted),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
