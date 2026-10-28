// The pre-trip card (specs/013-m08-home-result, contracts/pre-trip-card.md,
// `PreTrip`, FR-023–FR-033): the trip's briefing in the sheet, the body
// scrolling above «اطلع», which stays pinned. Closing spends nothing; the
// trip charges the liter when it starts (M02).
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/content/content_providers.dart';
import 'package:wassal/core/economy/economy_providers.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/progress/application/player_progress_provider.dart';
import 'package:wassal/core/progress/domain/unlocks.dart';
import 'package:wassal/core/routing/nav_guard.dart';
import 'package:wassal/core/theme/components/app_icon.dart';
import 'package:wassal/core/theme/components/buttons.dart';
import 'package:wassal/core/theme/components/pills.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/home/application/home_model.dart';
import 'package:wassal/features/home/application/start_next_trip.dart';
import 'package:wassal/features/onboarding/onboarding_providers.dart';
import 'package:wassal/features/pre_trip/application/booster_purchase.dart';
import 'package:wassal/features/pre_trip/application/briefing_provider.dart';
import 'package:wassal/features/pre_trip/domain/briefing.dart';
import 'package:wassal/features/pre_trip/presentation/booster_tiles.dart';
import 'package:wassal/features/pre_trip/presentation/buy_dialog.dart';
import 'package:wassal/features/pre_trip/presentation/new_card.dart';
import 'package:wassal/features/pre_trip/presentation/star_goals.dart';
import 'package:wassal/features/pre_trip/presentation/stop_prices.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

class PreTripCard extends ConsumerStatefulWidget {
  const PreTripCard({required this.tripId, super.key});

  final String tripId;

  static const goKey = Key('PreTripCard.go');
  static const closeKey = Key('PreTripCard.close');
  static const scrollKey = Key('PreTripCard.scroll');
  static const storyBarKey = Key('PreTripCard.storyBar');

  /// `PreTrip`'s gutter is 16 and its foot 24; the shared sheet's are 14.
  static const double _sideExtra = SpaceTokens.s2;
  static const double _footExtra = SpaceTokens.s10;

  /// The gap above «اطلع» (`PreTrip` boxes 56, 58).
  static const double _goGap = 20;

  @override
  ConsumerState<PreTripCard> createState() => _PreTripCardState();
}

class _PreTripCardState extends ConsumerState<PreTripCard> {
  late final _purchase = BoosterPurchase(
    ref.read(economyProvider).requireValue,
  );
  bool _leaving = false;

  /// A trip the pack lacks, or one not open: back to الموقف, once.
  void _leave() {
    if (_leaving) return;
    _leaving = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) NavGuard.go(context, '/home');
    });
  }

  void _go() {
    final session = ref.read(firstSessionProvider);
    final fuel = homeFuelState(
      ref.read(economyViewProvider).fuel,
      lessonDue: session.fuelLessonDue(widget.tripId),
    );
    NavGuard.go(
      context,
      fuel == HomeFuelState.empty
          ? fuelSheetLocation
          : '/trip/${widget.tripId}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final briefing = ref.watch(tripBriefingProvider(widget.tripId));
    final open =
        briefing != null &&
        tripUnlocked(
          ref.watch(contentSourceProvider),
          ref.watch(playerProgressProvider),
          widget.tripId,
        );
    if (!open) {
      _leave();
      return const SizedBox.shrink();
    }
    final unlimited = ref.watch(
      economyViewProvider.select((view) => view.fuel.unlimitedUntilMs),
    );
    final l10n = AppLocalizations.of(context);
    final numbers = ref.watch(numberFormatterProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        PreTripCard._sideExtra,
        0,
        PreTripCard._sideExtra,
        PreTripCard._footExtra,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(briefing: briefing),
          const SizedBox(height: SpaceTokens.s12),
          Flexible(
            child: SingleChildScrollView(
              key: PreTripCard.scrollKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: SpaceTokens.s12,
                children: [
                  StopPrices(
                    stops: briefing.stops,
                    ruleLines: briefing.ruleLines,
                  ),
                  if (briefing.newSubject case final subject?)
                    NewCard(subject: subject),
                  StarGoals(earned: briefing.starsEarned),
                  if (!briefing.boostersHidden)
                    BoosterTiles(
                      tiles: briefing.boosters,
                      offer: briefing.buyOffer,
                      onBuy: () => _buy(briefing.buyOffer),
                    ),
                ],
              ),
            ),
          ),
          if (briefing.isStory && briefing.storyRuleNoFights) ...[
            const SizedBox(height: SpaceTokens.s12),
            const _StoryBar(),
          ],
          const SizedBox(height: PreTripCard._goGap),
          AppButton.primary(
            key: PreTripCard.goKey,
            label: l10n.preTripGo,
            semanticLabel: unlimited == null
                ? l10n.preTripA11yGo
                : l10n.preTripGo,
            trailing: unlimited == null
                ? CostChip(
                    amount: l10n.homeFuelCost(numbers.integer(1)),
                    large: true,
                  )
                : null,
            onTap: _go,
          ),
        ],
      ),
    );
  }

  void _buy(BuyOffer? offer) {
    if (offer == null) return;
    unawaited(
      showBuyDialog(
        context,
        booster: offer.booster,
        priceBonat: offer.priceBonat,
        purchase: _purchase,
      ),
    );
  }
}

/// The line over «المشوار ١٢», the story chip, and ✕ (`PreTrip` boxes
/// 9–11).
class _Header extends StatelessWidget {
  const _Header({required this.briefing});

  final TripBriefing briefing;

  /// From the grabber to the line's text (`PreTrip` box 9).
  static const double _top = SpaceTokens.s14;
  static const double _lineGap = SpaceTokens.s2;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Consumer(
      builder: (context, ref, _) {
        final numbers = ref.watch(numberFormatterProvider);
        return Padding(
          padding: const EdgeInsets.only(top: _top),
          child: Row(
            spacing: SpaceTokens.s12,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: _lineGap,
                  children: [
                    Text(
                      briefing.lineName,
                      style: DesignExtras.preTripLine.copyWith(
                        color: ColorTokens.inkMuted,
                      ),
                    ),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: SpaceTokens.s8,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(
                            l10n.preTripTitle(
                              numbers.integer(briefing.tripIndex),
                            ),
                            style: DesignExtras.preTripTitle.copyWith(
                              color: ColorTokens.ink,
                            ),
                          ),
                        ),
                        if (briefing.isStory)
                          StatusChip.story(label: l10n.tripStoryChip),
                      ],
                    ),
                  ],
                ),
              ),
              IconCircleButton(
                key: PreTripCard.closeKey,
                icon: 'close',
                semanticLabel: l10n.closeLabel,
                inSheet: true,
                onTap: () => unawaited(Navigator.of(context).maybePop()),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A story trip's condition, above «اطلع» (FR-033).
class _StoryBar extends StatelessWidget {
  const _StoryBar();

  static const double _height = 40;
  static const double _icon = 20;

  @override
  Widget build(BuildContext context) => Semantics(
    key: PreTripCard.storyBarKey,
    container: true,
    child: Container(
      constraints: const BoxConstraints(minHeight: _height),
      padding: const EdgeInsets.symmetric(
        horizontal: SpaceTokens.s12,
        vertical: SpaceTokens.s8,
      ),
      decoration: BoxDecoration(
        color: ColorTokens.danger,
        borderRadius: BorderRadius.circular(RadiusTokens.tray),
      ),
      child: Row(
        spacing: SpaceTokens.s8,
        children: [
          const AppIcon('shield_check', size: _icon),
          Expanded(
            child: Text(
              AppLocalizations.of(context).tripStoryNoFights,
              style: TypeTokens.caption
                  .weight(600)
                  .copyWith(color: ColorTokens.ink),
            ),
          ),
        ],
      ),
    ),
  );
}
