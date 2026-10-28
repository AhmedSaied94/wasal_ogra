// The result (specs/013-m08-home-result, contracts/result.md, `Result`):
// what the trip paid and why, from the trip's own result. Opened without
// the trip's hand-over, it shows the last result's pay only; with nothing
// to show, it goes Home. Back goes Home.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/art/rive_art.dart';
import 'package:wassal/core/audio_haptics/audio_haptics_providers.dart';
import 'package:wassal/core/audio_haptics/sfx.dart';
import 'package:wassal/core/content/content_providers.dart';
import 'package:wassal/core/economy/economy_providers.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/progress/application/player_progress_provider.dart';
import 'package:wassal/core/routing/nav_guard.dart';
import 'package:wassal/core/theme/components/buttons.dart';
import 'package:wassal/core/theme/components/containers.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/home/application/home_model.dart';
import 'package:wassal/features/home/application/last_finished_trip.dart';
import 'package:wassal/features/home/application/start_next_trip.dart';
import 'package:wassal/features/onboarding/onboarding_providers.dart';
import 'package:wassal/features/onboarding/presentation/first_session_continue.dart';
import 'package:wassal/features/result/application/result_model.dart';
import 'package:wassal/features/result/application/result_slots.dart';
import 'package:wassal/features/result/domain/result_args.dart';
import 'package:wassal/features/result/domain/summary.dart';
import 'package:wassal/features/result/presentation/apartment_card.dart';
import 'package:wassal/features/result/presentation/breakdown_card.dart';
import 'package:wassal/features/result/presentation/mistakes_card.dart';
import 'package:wassal/features/result/presentation/pay_block.dart';
import 'package:wassal/features/result/presentation/quote_card.dart';
import 'package:wassal/features/result/presentation/result_stars.dart';
import 'package:wassal/features/result/presentation/share_action.dart';
import 'package:wassal/features/trip/trip_providers.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

class ResultScreen extends ConsumerStatefulWidget {
  const ResultScreen({required this.tripId, this.args, super.key});

  final String tripId;

  /// What the trip handed over; null when the route was opened another
  /// way.
  final ResultArgs? args;

  static const backKey = Key('ResultScreen.back');
  static const titleKey = Key('ResultScreen.title');
  static const againKey = Key('ResultScreen.again');
  static const recordKey = Key('ResultScreen.record');
  static const confettiKey = Key('ResultScreen.confetti');
  static const scrollKey = Key('ResultScreen.scroll');

  @override
  ConsumerState<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends ConsumerState<ResultScreen> {
  /// `Result`'s padding: 16 at the sides, 24 under the last block.
  static const EdgeInsets _padding = EdgeInsets.fromLTRB(
    LayoutTokens.gutter,
    0,
    LayoutTokens.gutter,
    SpaceTokens.s24,
  );

  bool _left = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _opened());
  }

  /// A finished trip's result: Home follows its line, and a first three
  /// stars sounds the horn (FR-045), once.
  void _opened() {
    if (!mounted) return;
    final model = ref.read(resultModelProvider(widget.tripId, widget.args));
    if (model is! FullResult) return;
    ref.read(lastFinishedTripProvider.notifier).tripId = widget.tripId;
    if (model.summary.firstThreeStars &&
        ref.read(tripSettingsProvider).soundOn) {
      ref.read(sfxPlayerProvider).play(Sfx.horn);
    }
  }

  void _home() {
    if (_left) return;
    _left = true;
    context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final model = ref.watch(resultModelProvider(widget.tripId, widget.args));
    if (model is NoResult) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _home();
      });
      return const ColoredBox(color: ColorTokens.ground);
    }
    final l10n = AppLocalizations.of(context);
    final numbers = ref.watch(numberFormatterProvider);
    final full = model is FullResult ? model : null;
    final summary = full?.summary;
    final (heading, pay, apartment) = switch (model) {
      FullResult(:final summary, :final apartment) => (
        summary.heading,
        summary.payJenehat,
        apartment,
      ),
      PayOnlyResult(:final heading, :final payJenehat, :final apartment) => (
        heading,
        payJenehat,
        apartment,
      ),
      NoResult() => throw StateError('handled above'),
    };
    final task = full == null ? null : ref.watch(resultTaskSlotProvider);
    final double = full == null ? null : ref.watch(resultDoubleSlotProvider);
    final doubled =
        full != null &&
        ref.watch(
          economyViewProvider.select((view) {
            final last = view.lastResult;
            return last != null &&
                last.startTxn == full.args.startTxn &&
                last.doubled;
          }),
        );
    final celebrate = summary?.firstThreeStars ?? false;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _home();
      },
      child: Scaffold(
        backgroundColor: ColorTokens.ground,
        body: SingleChildScrollView(
          key: ResultScreen.scrollKey,
          padding: _padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: SpaceTokens.s12,
            children: [
              _Header(
                title: heading == null
                    ? ''
                    : l10n.resultHeader(
                        numbers.integer(heading.tripIndex),
                        heading.lineName,
                      ),
                onBack: _home,
              ),
              if (task != null)
                Semantics(
                  liveRegion: true,
                  child: Builder(builder: task.banner),
                ),
              if (heading != null)
                Column(
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        l10n.resultTitle(heading.lastStop),
                        key: ResultScreen.titleKey,
                        textAlign: TextAlign.center,
                        style: DesignExtras.resultTitle.copyWith(
                          color: ColorTokens.ink,
                        ),
                      ),
                    ),
                    if (celebrate)
                      Text(
                        l10n.resultRecord,
                        key: ResultScreen.recordKey,
                        textAlign: TextAlign.center,
                        style: TypeTokens.displayS.copyWith(
                          color: ColorTokens.primary,
                        ),
                      ),
                  ],
                ),
              if (full != null) ...[
                _StarsAndQuote(
                  summary: full.summary,
                  args: full.args,
                  celebrate: celebrate,
                ),
                BreakdownCard(breakdown: full.summary.breakdown),
                if (full.summary.summary case final mistakes?)
                  MistakesCard(
                    summary: mistakes,
                    lines: full.summary.mistakeLines,
                  ),
              ],
              PayBlock(payJenehat: pay, bonat: task?.bonat),
              if (full != null && double != null && !doubled)
                double(context, full.args),
              ApartmentCard(progress: apartment),
              _BottomRow(
                tripId: widget.tripId,
                isStory: heading?.isStory ?? false,
                // The picture needs the stars: a full result's only.
                share: full == null
                    ? null
                    : ShareResultButton(summary: full.summary, args: full.args),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `Result` block 1: back «ارجع الموقف» at the start, the trip and its
/// line centred.
class _Header extends StatelessWidget {
  const _Header({required this.title, required this.onBack});

  final String title;
  final VoidCallback onBack;

  /// `Result` box 1's row.
  static const double _height = 48;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(top: screenTopInset(context)),
    child: SizedBox(
      height: _height,
      child: Row(
        spacing: SpaceTokens.s12,
        children: [
          IconCircleButton(
            key: ResultScreen.backKey,
            icon: 'back',
            semanticLabel: AppLocalizations.of(context).resultA11yBack,
            onTap: onBack,
          ),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: DesignExtras.resultHeader.copyWith(
                color: ColorTokens.inkMuted,
              ),
            ),
          ),
          const SizedBox(width: IconCircleButton.size),
        ],
      ),
    ),
  );
}

/// The stars, with the confetti over them on a first three stars, then the
/// quote, which takes no space until it arrives.
class _StarsAndQuote extends StatelessWidget {
  const _StarsAndQuote({
    required this.summary,
    required this.args,
    required this.celebrate,
  });

  final ResultSummary summary;
  final ResultArgs args;
  final bool celebrate;

  /// The `Confetti` artboard's frame.
  static const Size _confetti = Size(390, 300);

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          ResultStars(stars: summary.stars, rows: summary.starRows),
          if (celebrate && !MediaQuery.disableAnimationsOf(context))
            Positioned(
              child: IgnorePointer(
                child: ExcludeSemantics(
                  child: SizedBox.fromSize(
                    key: ResultScreen.confettiKey,
                    size: _confetti,
                    child: RiveArtView(
                      artboard: 'Confetti',
                      bind: (model) => model.trigger('play')?.trigger(),
                      fallback: const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      QuoteCard(args: args, gap: SpaceTokens.s12),
    ],
  );
}

/// `Result` block 12: M07's «كمّل» while it shows, else «مشوار تاني» with
/// its liter (none in an unlimited window); beside it, a full result's
/// share button.
class _BottomRow extends ConsumerStatefulWidget {
  const _BottomRow({
    required this.tripId,
    required this.isStory,
    required this.share,
  });

  final String tripId;
  final bool isStory;

  /// The share button beside it, when there is a picture to share.
  final Widget? share;

  @override
  ConsumerState<_BottomRow> createState() => _BottomRowState();
}

class _BottomRowState extends ConsumerState<_BottomRow> {
  /// `Result` boxes 56 and 58.
  static const double _height = 60;
  static const double _chipHeight = 26;
  static const double _gap = SpaceTokens.s10;

  bool _busy = false;

  Future<void> _again() async {
    if (_busy) return;
    _busy = true;
    try {
      if (widget.isStory) {
        await ref.read(storyAfterResultProvider).after(widget.tripId);
      }
      if (!mounted) return;
      // Computed after this result: the line's next trip.
      final next = homeNextTrip(
        ref.read(contentSourceProvider),
        ref.read(playerProgressProvider),
        ref.read(firstSessionProvider),
        lastFinishedTripId: widget.tripId,
      );
      if (next == null) {
        NavGuard.go(context, '/home');
        return;
      }
      await startNextTrip(
        context,
        ref,
        tripId: next.tripId,
        from: StartFrom.result,
      );
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(firstSessionProvider);
    final continues =
        session.inFirstSession ||
        ref.watch(tutorialEndedOnProvider) == widget.tripId;
    final main = continues
        ? FirstSessionContinue(tripId: widget.tripId)
        : _againButton(context);
    final share = widget.share;
    if (share == null) return main;
    return Row(
      spacing: _gap,
      children: [
        Expanded(child: main),
        share,
      ],
    );
  }

  Widget _againButton(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final numbers = ref.watch(numberFormatterProvider);
    final window = ref.watch(
      economyViewProvider.select((view) => view.fuel.unlimitedUntilMs != null),
    );
    return AppButton.secondary(
      key: ResultScreen.againKey,
      label: l10n.resultAgain,
      height: _height,
      semanticLabel: window ? l10n.resultAgain : l10n.resultA11yAgain,
      trailing: window
          ? null
          : Container(
              height: _chipHeight,
              padding: const EdgeInsets.symmetric(horizontal: SpaceTokens.s8),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: ColorTokens.sunSoft,
                borderRadius: BorderRadius.circular(RadiusTokens.pill),
              ),
              child: Text(
                l10n.resultAgainFuel(numbers.integer(1)),
                style: TypeTokens.label
                    .weight(700)
                    .copyWith(color: ColorTokens.ink),
              ),
            ),
      onTap: () => unawaited(_again()),
    );
  }
}
