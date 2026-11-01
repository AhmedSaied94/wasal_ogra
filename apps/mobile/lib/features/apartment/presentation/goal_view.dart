// الشقة before chapter 4 (specs/015-m10-apartment-story, contracts/
// apartment.md "The goal view", HANDOFF `AptGoal`, `AptGoalReady`,
// research R8): the current chapter's goal, its art, its line, the ready
// state and the apartment teaser.
import 'dart:async';
import 'dart:math' show min;

import 'package:content_models/content_models.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/art/apartment_art.dart';
import 'package:wassal/core/content/content_providers.dart';
import 'package:wassal/core/content/domain/story_characters.dart';
import 'package:wassal/core/economy/domain/wire.dart';
import 'package:wassal/core/economy/economy_providers.dart';
import 'package:wassal/core/progress/application/player_progress_provider.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/routing/nav_guard.dart';
import 'package:wassal/core/theme/components/app_icon.dart';
import 'package:wassal/core/theme/components/characters.dart';
import 'package:wassal/core/theme/components/vehicle_sprite.dart';
import 'package:wassal/core/theme/components/buttons.dart';
import 'package:wassal/core/theme/components/containers.dart';
import 'package:wassal/core/theme/components/pills.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/apartment/application/apartment_providers.dart';
import 'package:wassal/features/apartment/application/goal_purchase.dart';
import 'package:wassal/features/apartment/domain/goal_view_model.dart';
import 'package:wassal/features/apartment/presentation/chapter_bar.dart';
import 'package:wassal/features/apartment/presentation/goal_headline.dart';
import 'package:wassal/features/apartment/presentation/price_chip.dart';
import 'package:wassal/features/lines/presentation/vehicle_art.dart';
import 'package:wassal/features/home/domain/savings_target.dart'
    show Amount, Count;
import 'package:wassal/l10n/generated/app_localizations.dart';

/// `AptGoal`'s art height, and the column's gap.
const double goalArtHeight = 190;
const double apartmentGap = SpaceTokens.s10;

class ApartmentGoalView extends ConsumerStatefulWidget {
  const ApartmentGoalView({
    required this.model,
    required this.onBought,
    super.key,
  });

  final GoalViewModel model;

  /// What follows a bought goal, which belongs to the screen that stays:
  /// buying the goal makes the next chapter current, so this view is usually
  /// gone before the purchase returns.
  final Future<void> Function(Chapter chapter) onBought;

  static const buyKey = Key('ApartmentGoal.buy');
  static const readyKey = Key('ApartmentGoal.ready');

  @override
  ConsumerState<ApartmentGoalView> createState() => _ApartmentGoalViewState();
}

class _ApartmentGoalViewState extends ConsumerState<ApartmentGoalView> {
  bool _announced = false;

  @override
  void initState() {
    super.initState();
    if (widget.model.ready) _announceLater();
  }

  @override
  void didUpdateWidget(ApartmentGoalView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.model.ready && !oldWidget.model.ready) _announceLater();
  }

  /// «{goal} جاهزة» once the ready state draws (contracts/apartment.md).
  void _announceLater() {
    if (_announced) return;
    _announced = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      unawaited(
        SemanticsService.sendAnnouncement(
          View.of(context),
          l10n.apartmentGoalReadyA11y(
            widget.model.target.subjectName,
            widget.model.genderCode,
          ),
          TextDirection.rtl,
        ),
      );
    });
  }

  Future<void> _buy() async {
    final purchase = ref.read(goalPurchaseProvider);
    final chapter = widget.model.chapter;
    final onBought = widget.onBought;
    final result = await purchase.buy(
      ref.read(contentSourceProvider),
      ref.read(playerProgressProvider),
      chapter,
    );
    // No `mounted` guard: nothing below touches this state.
    switch (result) {
      case GoalBought():
        await onBought(chapter);
      case GoalNotAllowed() || GoalRefused() || GoalWriteFailed():
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final numbers = ref.watch(numberFormatterProvider);
    final model = widget.model;
    final target = model.target;
    final figures = switch (target.progress) {
      final Amount progress => l10n.aptGoalProgress(
        numbers.integer(min(progress.have, progress.of)),
        numbers.integer(progress.of),
      ),
      final Count progress => l10n.aptGoalTrips(
        numbers.integer(progress.done),
        numbers.integer(progress.of),
      ),
    };
    final progressA11y = switch (target.progress) {
      final Amount progress => l10n.aptGoalProgressA11y(
        target.subjectName,
        numbers.integer(min(progress.have, progress.of)),
        numbers.integer(progress.of),
      ),
      final Count progress => l10n.aptGoalTripsA11y(
        l10n.aptGoalFinishLine(target.subjectName),
        numbers.integer(progress.done),
        numbers.integer(progress.of),
      ),
    };
    final top = MediaQuery.paddingOf(context).top;
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            LayoutTokens.gutter,
            top,
            LayoutTokens.gutter,
            0,
          ),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              _Header(title: l10n.aptGoalTitle),
              const SizedBox(height: apartmentGap),
              ChapterBar(
                title: Text(
                  l10n.aptGoalChapterBar(
                    numbers.integer(model.chapter.order),
                    model.chapter.title.arEg,
                  ),
                  maxLines: 2,
                  style: TypeTokens.displayS.copyWith(color: ColorTokens.paper),
                ),
                trailing: l10n.aptGoalAllChapters,
                semanticLabel: l10n.aptGoalChapterA11y(
                  numbers.integer(model.chapter.order),
                  model.chapter.title.arEg,
                ),
              ),
              const SizedBox(height: apartmentGap),
              _GoalCard(
                model: model,
                figures: figures,
                progressA11y: progressA11y,
              ),
              if (model.ready) ...[
                const SizedBox(height: apartmentGap),
                _BuyButton(model: model, onTap: _buy),
              ],
              const SizedBox(height: apartmentGap),
            ]),
          ),
        ),
        // The teaser takes what is left down to the nav, as the boards draw
        // it (AptGoal 20, AptGoalLine 20, AptGoalVehicle 24).
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              LayoutTokens.gutter,
              0,
              LayoutTokens.gutter,
              SpaceTokens.s12,
            ),
            child: _Teaser(model: model),
          ),
        ),
      ],
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.title});

  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final numbers = ref.watch(numberFormatterProvider);
    final jenehat = ref.watch(economyViewProvider).jenehat;
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TypeTokens.displayL,
            ),
          ),
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

class _GoalCard extends StatelessWidget {
  const _GoalCard({
    required this.model,
    required this.figures,
    required this.progressA11y,
  });

  final GoalViewModel model;
  final String figures;
  final String progressA11y;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final target = model.target;
    return AppCard(
      radius: RadiusTokens.scene,
      lip: LipTokens.cardBig,
      padding: const EdgeInsets.all(SpaceTokens.s14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: SpaceTokens.s12,
        children: [
          _GoalArt(model: model),
          // `AptGoalLine` and `AptGoalVehicle` block 3b: the name 41 high and
          // the figures on its row, or under it when the name is long.
          GoalHeadline(
            name: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 41),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                widthFactor: 1,
                child: Text(
                  target.progress is Count
                      ? l10n.aptGoalFinishLine(target.subjectName)
                      : target.subjectName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TypeTokens.displayM,
                ),
              ),
            ),
            figures: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: SpaceTokens.s6,
              children: [
                if (model.ready)
                  _ReadyChip(label: l10n.apartmentGoalReady(model.genderCode)),
                Text(
                  figures,
                  maxLines: 1,
                  style: DesignExtras.piecePriceHave.copyWith(
                    color: ColorTokens.ink,
                  ),
                ),
              ],
            ),
          ),
          _GoalProgress(model: model, semanticLabel: progressA11y),
          if (model.line case final line?) _Line(line: line),
        ],
      ),
    );
  }
}

/// «جاهز!» beside the amount: the third station green with `ink` (`AptGoalReady`
/// and `AptGoalVehicle` draw it 19 high, shorter than a `StatusChip`).
class _ReadyChip extends StatelessWidget {
  const _ReadyChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: SpaceTokens.s8,
      vertical: 1,
    ),
    decoration: BoxDecoration(
      color: StationColors.all[2].bg,
      borderRadius: BorderRadius.circular(RadiusTokens.pill),
    ),
    child: Text(
      label,
      style: DesignExtras.chipLabel.copyWith(color: ColorTokens.ink),
    ),
  );
}

/// The bar, animated from the value the chapter was last drawn at (R8).
class _GoalProgress extends ConsumerStatefulWidget {
  const _GoalProgress({required this.model, required this.semanticLabel});

  final GoalViewModel model;
  final String semanticLabel;

  @override
  ConsumerState<_GoalProgress> createState() => _GoalProgressState();
}

class _GoalProgressState extends ConsumerState<_GoalProgress> {
  double? _from;

  @override
  Widget build(BuildContext context) {
    final value = widget.model.target.progress.fraction;
    final id = widget.model.chapter.chapterId;
    // Read now, stored after the frame: a provider can't change while the
    // tree builds.
    _from ??= ref.read(goalBarSeenProvider)[id] ?? 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(goalBarSeenProvider.notifier).take(id, value);
    });
    final from = _from ?? value;
    return Semantics(
      label: widget.semanticLabel,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: from, end: value),
        duration: MotionTokens.sheetIn,
        curve: MotionTokens.sheetInCurve,
        builder: (context, shown, _) => ProgressBar(
          value: shown,
          // Gold is for savings, primary for trips (§3.3).
          color: widget.model.target.progress is Count
              ? ProgressColor.primary
              : ProgressColor.gold,
          height: 14,
        ),
      ),
    );
  }
}

class _GoalArt extends StatelessWidget {
  const _GoalArt({required this.model});

  final GoalViewModel model;

  @override
  Widget build(BuildContext context) {
    final art = model.art;
    final slug = art is DrawnGoal ? art.slug : null;
    final asset = slug == null ? null : ApartmentArt.goal(slug);
    final radius = BorderRadius.circular(RadiusTokens.l);
    return Container(
      height: goalArtHeight,
      decoration: BoxDecoration(
        color: ColorTokens.sunSoft,
        borderRadius: radius,
      ),
      clipBehavior: Clip.antiAlias,
      child: Center(
        child: asset == null
            ? _FallbackArt(art: model.fallbackArt)
            : SvgPicture.asset(asset, fit: BoxFit.contain),
      ),
    );
  }
}

class _FallbackArt extends StatelessWidget {
  const _FallbackArt({required this.art});

  final GoalArt art;

  @override
  Widget build(BuildContext context) => switch (art) {
    VehicleGoal(:final vehicleId) => SizedBox.fromSize(
      size: VehicleSprite.size,
      child: VehicleSprite(
        vehicle: vehicleId,
        fallback: VehicleArt(vehicle: vehicleId),
      ),
    ),
    // The line's own vehicle stands in for the board's tuktuk on the road.
    TuktukGoal() => SizedBox.fromSize(
      size: VehicleSprite.size,
      child: const VehicleArt(vehicle: VehicleId.tuktuk),
    ),
    RingGoal() ||
    DrawnGoal() => const AppIcon('ring_gem', size: 96, color: ColorTokens.sun),
  };
}

class _Line extends StatelessWidget {
  const _Line({required this.line});

  final CharacterLine line;

  @override
  Widget build(BuildContext context) {
    final speaker = storyCharacterArt(line.speaker);
    // `AptGoalLine` block 3d: 66 high (the 46 avatar and 10 around it), up to
    // two lines beside it.
    return Container(
      constraints: const BoxConstraints(minHeight: 66),
      padding: const EdgeInsets.symmetric(
        horizontal: SpaceTokens.s12,
        vertical: SpaceTokens.s10,
      ),
      decoration: BoxDecoration(
        color: ColorTokens.ground,
        borderRadius: BorderRadius.circular(RadiusTokens.bubble),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: SpaceTokens.s10,
        children: [
          ClipOval(
            child: SizedBox(
              width: 46,
              height: 46,
              child: FittedBox(
                fit: BoxFit.cover,
                child: CharacterAvatar(speaker),
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: SpaceTokens.s4,
              children: [
                Text(line.text.arEg, style: TypeTokens.quote),
                Text(
                  AppLocalizations.of(context).sceneSpeaker(speaker),
                  style: TypeTokens.label.copyWith(color: ColorTokens.inkMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BuyButton extends ConsumerWidget {
  const _BuyButton({required this.model, required this.onTap});

  final GoalViewModel model;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final numbers = ref.watch(numberFormatterProvider);
    final goal = model.target.subjectName;
    final price = switch (model.action) {
      BuyChapter(:final price) || OpenVehicleSheet(:final price) => price,
      NoAction() => 0,
    };
    return AppButton.primary(
      key: ApartmentGoalView.buyKey,
      label: switch (model.action) {
        OpenVehicleSheet(:final vehicleId) => l10n.apartmentBuyVehicle(
          vehicleWire[vehicleId]!,
        ),
        _ => l10n.apartmentBuyGoal(goal),
      },
      semanticLabel: l10n.apartmentBuyGoalA11y(goal, numbers.integer(price)),
      height: LayoutTokens.ctaH,
      radius: LayoutTokens.ctaRadius,
      trailing: price == 0
          ? null
          : PriceChip(label: l10n.aptGoalPrice(numbers.integer(price))),
      onTap: () {
        if (model.action is OpenVehicleSheet) {
          NavGuard.go(
            context,
            '/lines/vehicle/${vehicleWire[(model.action as OpenVehicleSheet).vehicleId]!}',
          );
          return;
        }
        onTap();
      },
    );
  }
}

class _Teaser extends StatelessWidget {
  const _Teaser({required this.model});

  final GoalViewModel model;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      // 100 high around the 96 drawing and the 2 ring, as the boards draw it,
      // its content centred when the card takes the rest of the screen.
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: SpaceTokens.s14),
      decoration: BoxDecoration(
        color: ColorTokens.paper,
        borderRadius: BorderRadius.circular(RadiusTokens.xl),
        border: Border.all(color: ColorTokens.outline, width: 2),
      ),
      child: Row(
        spacing: SpaceTokens.s12,
        children: [
          // The room first, at the start side (the boards' 240 to 360).
          SvgPicture.asset(ApartmentArt.teaserRoom, width: 120, height: 96),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: SpaceTokens.s4,
              children: [
                Row(
                  spacing: SpaceTokens.s6,
                  children: [
                    const AppIcon(
                      'lock',
                      size: 18,
                      color: ColorTokens.inkMuted,
                    ),
                    Text(l10n.apartmentTitle, style: TypeTokens.displayS),
                  ],
                ),
                Text(
                  l10n.aptGoalLockedBody,
                  style: TypeTokens.caption.copyWith(color: ColorTokens.ink2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
