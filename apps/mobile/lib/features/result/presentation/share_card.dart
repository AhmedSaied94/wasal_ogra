// The result as a picture (specs/013-m08-home-result, contracts/result.md
// "Sharing", `ShareCard`): 360×360 on `sun` with its two glows, the trip,
// «وصلنا …!», the stars, the quote when there is one, the wordmark and the
// pay. Drawn still, at text scale 1, in the player's digits; the share
// action renders it at 3× (1080×1080).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/theme/components/app_icon.dart';
import 'package:wassal/core/theme/components/avatars.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/result/domain/summary.dart';
import 'package:wassal/features/trip/domain/looks.dart';
import 'package:wassal/features/trip/presentation/trip_text.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

/// The quote as the picture shows it: the face, the words and who said
/// them.
typedef ShareQuote = ({Look look, String line, String labelKey});

/// What the picture shows.
final class ShareSpec {
  const ShareSpec({
    required this.heading,
    required this.stars,
    required this.payJenehat,
    this.quote,
  });

  final ResultHeading heading;
  final int stars;

  /// The final pay: doubled when it was.
  final int payJenehat;
  final ShareQuote? quote;
}

class ShareCard extends ConsumerWidget {
  const ShareCard({required this.spec, super.key});

  final ShareSpec spec;

  /// The artboard's side; the picture is three times it.
  static const double side = 360;

  /// The icons the picture draws, each in the colour it is drawn in: the
  /// share action loads them first.
  static const icons = [
    ('star_gold_ink', ColorTokens.ink),
    ('star', ColorTokens.sunLip),
    ('star_ink', ColorTokens.sunSoft),
    ('coin', ColorTokens.ink),
  ];

  static const quoteKey = Key('ShareCard.quote');
  static const starsKey = Key('ShareCard.stars');

  /// `ShareCard` boxes 5–7, right to left.
  static const _starSizes = [48.0, 62.0, 48.0];
  static const double _starGap = 6;
  static const EdgeInsets _padding = EdgeInsets.fromLTRB(22, 26, 22, 20);
  static const double _coin = 20;

  /// The two `sun.glow` circles: centre and radius, from the top-left.
  static const _glows = [(Offset(320, 40), 80.0), (Offset(30, 330), 90.0)];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final numbers = ref.watch(numberFormatterProvider);
    final heading = spec.heading;
    final stars = Row(
      key: starsKey,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      spacing: _starGap,
      children: [
        for (final (i, size) in _starSizes.indexed)
          _ShareStar(earned: i < spec.stars, size: size),
      ],
    );
    final content = Column(
      spacing: SpaceTokens.s10,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: SpaceTokens.s12,
            vertical: SpaceTokens.s2,
          ),
          decoration: BoxDecoration(
            color: ColorTokens.paper,
            borderRadius: BorderRadius.circular(RadiusTokens.pill),
          ),
          child: Text(
            l10n.resultHeader(
              numbers.integer(heading.tripIndex),
              heading.lineName,
            ),
            style: DesignExtras.shareChip.copyWith(color: ColorTokens.ink),
          ),
        ),
        Text(
          l10n.resultTitle(heading.lastStop),
          textAlign: TextAlign.center,
          style: DesignExtras.shareTitle.copyWith(color: ColorTokens.ink),
        ),
        if (spec.quote case final quote?) ...[
          stars,
          _QuoteCard(key: quoteKey, quote: quote),
          const Spacer(),
        ] else
          // No quote: the stars take the middle.
          Expanded(child: Center(child: stars)),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              l10n.appName,
              style: DesignExtras.shareWordmark.copyWith(
                color: ColorTokens.ink,
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              spacing: SpaceTokens.s4,
              children: [
                const AppIcon('coin', size: _coin, color: ColorTokens.ink),
                Text(
                  l10n.sharePaid(numbers.integer(spec.payJenehat)),
                  style: DesignExtras.sharePaid.copyWith(
                    color: ColorTokens.ink,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
    // A picture: still (the static art, not Rive), and at its own size
    // whatever the player's text scale.
    return MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.noScaling, disableAnimations: true),
      child: SizedBox.square(
        dimension: side,
        child: ClipRect(
          child: ColoredBox(
            color: ColorTokens.sun,
            child: Stack(
              children: [
                for (final (centre, radius) in _glows)
                  Positioned(
                    left: centre.dx - radius,
                    top: centre.dy - radius,
                    width: radius * 2,
                    height: radius * 2,
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        color: ColorTokens.sunGlow,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                Positioned.fill(
                  // Its own text style: an overlay has no `Material` above.
                  child: DefaultTextStyle(
                    style: TypeTokens.body.copyWith(color: ColorTokens.ink),
                    child: Padding(padding: _padding, child: content),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// An earned star in gold with an `ink` outline; a missed one in
/// `sun.soft` with a `sun.lip` outline.
class _ShareStar extends StatelessWidget {
  const _ShareStar({required this.earned, required this.size});

  final bool earned;
  final double size;

  @override
  Widget build(BuildContext context) => earned
      ? AppIcon('star_gold_ink', size: size, color: ColorTokens.ink)
      : SizedBox.square(
          dimension: size,
          child: Stack(
            children: [
              AppIcon('star', size: size, color: ColorTokens.sunLip),
              AppIcon('star_ink', size: size, color: ColorTokens.sunSoft),
            ],
          ),
        );
}

/// `ShareCard` box 8: the face, «{line}» and who said it, on `paper` with
/// the `sun` lip.
class _QuoteCard extends StatelessWidget {
  const _QuoteCard({required this.quote, super.key});

  final ShareQuote quote;

  static const int _maxLines = 2;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SpaceTokens.s12,
        vertical: SpaceTokens.s10,
      ),
      decoration: BoxDecoration(
        color: ColorTokens.paper,
        borderRadius: BorderRadius.circular(RadiusTokens.l),
        boxShadow: const [LipTokens.sun],
      ),
      child: Row(
        spacing: SpaceTokens.s10,
        children: [
          PassengerAvatar(
            lookId: quote.look.id,
            person: quote.look.rive,
            size: PassengerAvatarSize.share,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.resultQuote(quote.line),
                  maxLines: _maxLines,
                  overflow: TextOverflow.ellipsis,
                  style: DesignExtras.shareQuote.copyWith(
                    color: ColorTokens.ink,
                  ),
                ),
                Text(
                  l10n.lookLabel(quote.labelKey),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
