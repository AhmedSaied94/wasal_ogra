// The album (specs/015-m10-apartment-story, contracts/scene-viewer.md "The
// album", research R13, Q3), built to the `Album` artboard: every scene of
// the pack as a card, the unlocked ones to watch again and the locked ones
// as a tease.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/art/panel_art.dart';
import 'package:wassal/core/content/content_providers.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/progress/application/player_progress_provider.dart';
import 'package:wassal/core/routing/nav_guard.dart';
import 'package:wassal/core/theme/components/app_icon.dart';
import 'package:wassal/core/theme/components/containers.dart';
import 'package:wassal/core/theme/components/pressable.dart';
import 'package:wassal/core/theme/components/system_bars.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/lines/presentation/locked_fill.dart';
import 'package:wassal/features/story/domain/album.dart';
import 'package:wassal/features/story/domain/panel_ref.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

class AlbumPage extends ConsumerWidget {
  const AlbumPage({super.key});

  /// The header's «{n} من {total}».
  static const countKey = Key('AlbumPage.count');

  static Key cardKey(String sceneId) => ValueKey('AlbumPage.card.$sceneId');

  static const double _gap = SpaceTokens.s12;

  void _back(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/apartment/chapters');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final numbers = ref.watch(numberFormatterProvider);
    final (cards, unlocked, total) = album(
      ref.watch(contentSourceProvider),
      ref.watch(playerProgressProvider),
    );
    return SystemBars(
      bottom: ColorTokens.ground,
      child: Scaffold(
        backgroundColor: ColorTokens.ground,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ScreenHeader(
              title: l10n.albumTitle,
              fitTitle: true,
              onBack: () => _back(context),
              trailing: [
                _CountChip(
                  key: countKey,
                  label: l10n.albumCount(
                    numbers.integer(unlocked),
                    numbers.integer(total),
                  ),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: SpaceTokens.s14,
                  children: [
                    Text(
                      l10n.albumIntro,
                      style: DesignExtras.albumIntro.copyWith(
                        color: ColorTokens.ink2,
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: _gap,
                      children: [
                        for (var i = 0; i < cards.length; i += 2)
                          IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              spacing: _gap,
                              // The first card at the start side: right, in RTL.
                              children: [
                                Expanded(child: _Card(card: cards[i])),
                                Expanded(
                                  child: i + 1 < cards.length
                                      ? _Card(card: cards[i + 1])
                                      : const SizedBox.shrink(),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `Album` block 1: the scenes unlocked of all, a small white pill.
class _CountChip extends StatelessWidget {
  const _CountChip({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: SpaceTokens.s12,
      vertical: SpaceTokens.s2,
    ),
    decoration: BoxDecoration(
      color: ColorTokens.paper,
      borderRadius: BorderRadius.circular(RadiusTokens.pill),
    ),
    child: Text(
      label,
      style: DesignExtras.chipLabel.copyWith(color: ColorTokens.ink),
    ),
  );
}

class _Card extends ConsumerWidget {
  const _Card({required this.card});

  final AlbumCard card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final number = ref
        .watch(numberFormatterProvider)
        .integer(card.chapterNumber);
    return switch (card) {
      final UnlockedCard unlocked => _UnlockedCard(
        card: unlocked,
        number: l10n.chaptersNumber(number),
        sentence: l10n.albumCardA11y(
          'unlocked',
          number,
          unlocked.scene.title.arEg,
        ),
        watchAgain: l10n.albumWatchAgain,
      ),
      final LockedCard locked => _LockedCard(
        card: locked,
        number: l10n.chaptersNumber(number),
        sentence: l10n.albumCardA11y('locked', number, locked.title),
        line: l10n.albumLocked,
      ),
    };
  }
}

/// `Album` 3a: the first panel, the chapter and the title, and «اتفرج تاني»,
/// the whole card one button.
class _UnlockedCard extends StatelessWidget {
  const _UnlockedCard({
    required this.card,
    required this.number,
    required this.sentence,
    required this.watchAgain,
  });

  final UnlockedCard card;
  final String number;
  final String sentence;
  final String watchAgain;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(RadiusTokens.card);
    return Pressable(
      key: AlbumPage.cardKey(card.scene.sceneId),
      expand: true,
      onTap: () => NavGuard.push(
        context,
        Uri(
          path: '/story/scene/${card.scene.sceneId}',
          queryParameters: {'then': '/story/album'},
        ).toString(),
      ),
      lip: LipTokens.card,
      borderRadius: radius,
      semanticLabel: sentence,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: ColorTokens.paper,
          borderRadius: radius,
        ),
        child: Padding(
          padding: const EdgeInsets.all(DesignExtras.albumPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Thumb(panel: card.firstPanel),
              const SizedBox(height: SpaceTokens.s6),
              Text(
                number,
                style: DesignExtras.chapterNumber.copyWith(
                  color: ColorTokens.inkMuted,
                ),
              ),
              const SizedBox(height: SpaceTokens.s6),
              Text(
                card.scene.title.arEg,
                style: DesignExtras.chapterName.copyWith(
                  color: ColorTokens.ink,
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(
                  top: SpaceTokens.s8,
                  left: DesignExtras.albumButtonInset,
                  right: DesignExtras.albumButtonInset,
                  bottom: DesignExtras.albumButtonInset,
                ),
                child: Container(
                  height: DesignExtras.albumButtonHeight,
                  decoration: BoxDecoration(
                    color: ColorTokens.primarySoft,
                    borderRadius: BorderRadius.circular(
                      DesignExtras.albumButtonRadius,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    spacing: SpaceTokens.s8,
                    children: [
                      Text(
                        watchAgain,
                        style: DesignExtras.chapterAction.copyWith(
                          color: ColorTokens.primary,
                        ),
                      ),
                      const AppIcon(
                        'play',
                        size: 16,
                        color: ColorTokens.primary,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `Album` 3b: the locked look, a grey thumbnail with a lock, the chapter and
/// title in `ink.2`, and when it opens. Inert.
class _LockedCard extends StatelessWidget {
  const _LockedCard({
    required this.card,
    required this.number,
    required this.sentence,
    required this.line,
  });

  final LockedCard card;
  final String number;
  final String sentence;
  final String line;

  @override
  Widget build(BuildContext context) => Semantics(
    key: AlbumPage.cardKey(card.sceneId),
    container: true,
    label: sentence,
    child: ExcludeSemantics(
      child: DecoratedBox(
        decoration: lockedFill(BorderRadius.circular(RadiusTokens.card)),
        child: Padding(
          padding: const EdgeInsets.all(DesignExtras.albumPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: DesignExtras.albumThumbHeight,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: ColorTokens.track,
                    borderRadius: BorderRadius.circular(RadiusTokens.m),
                  ),
                  child: const Center(
                    child: AppIcon(
                      'lock_outline',
                      size: DesignExtras.albumLockSize,
                      color: ColorTokens.ink2,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: SpaceTokens.s6),
              Text(
                number,
                style: DesignExtras.chapterNumber.copyWith(
                  color: ColorTokens.ink2,
                ),
              ),
              const SizedBox(height: SpaceTokens.s6),
              Text(
                card.title,
                style: DesignExtras.chapterName.copyWith(
                  color: ColorTokens.ink2,
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(
                  top: SpaceTokens.s8,
                  left: DesignExtras.albumButtonInset,
                  right: DesignExtras.albumButtonInset,
                  bottom: DesignExtras.albumButtonInset,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: DesignExtras.albumButtonHeight,
                  ),
                  child: Text(
                    line,
                    style: DesignExtras.chapterNumber.copyWith(
                      color: ColorTokens.ink2,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// `Album` 3a: the scene's first panel, 96 high on its own ground.
class _Thumb extends StatelessWidget {
  const _Thumb({required this.panel});

  final PanelRef panel;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: ClipRRect(
      borderRadius: BorderRadius.circular(RadiusTokens.m),
      child: SizedBox(
        height: DesignExtras.albumThumbHeight,
        child: ColoredBox(
          color: PanelArt.groundFor(panel.art),
          child: PanelArt(slug: panel.art, speakers: panel.speakers),
        ),
      ),
    ),
  );
}
