// The rider's quote on the result (specs/013-m08-home-result, `Result`
// block 5, research R14): one line this trip's passengers said, with who
// said it. It takes no space until the replay picks it, then fades in.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:content_models/content_models.dart' show TripDefinition;
import 'package:wassal/core/content/content_providers.dart';
import 'package:wassal/core/content/domain/content_source.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/l10n/number_formatter.dart';
import 'package:wassal/core/theme/components/avatars.dart';
import 'package:wassal/core/theme/components/containers.dart';
import 'package:wassal/core/theme/components/station_tag.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/result/application/quote_provider.dart';
import 'package:wassal/features/result/domain/quote.dart';
import 'package:wassal/features/result/domain/result_args.dart';
import 'package:wassal/features/trip/domain/speech.dart';
import 'package:wassal/features/trip/presentation/trip_text.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

class QuoteCard extends ConsumerWidget {
  const QuoteCard({required this.args, this.gap = 0, super.key});

  final ResultArgs args;

  /// Space above the card, only when it shows.
  final double gap;

  static const lineKey = Key('QuoteCard.line');

  /// `Result` box 18.
  static const double _minHeight = 72;
  static const int _maxLines = 2;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quote = ref.watch(resultQuoteProvider(args)).value;
    final line = quote == null
        ? null
        : quoteLineOf(
            AppLocalizations.of(context),
            ref.watch(contentSourceProvider),
            ref.watch(numberFormatterProvider),
            quote,
            args.replay.definition,
          );
    if (quote == null || line == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final card = AppCard(
      padding: const EdgeInsets.symmetric(horizontal: SpaceTokens.s14),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: _minHeight),
        child: Row(
          spacing: SpaceTokens.s12,
          children: [
            PassengerAvatar(
              lookId: quote.look.id,
              person: quote.look.rive,
              size: PassengerAvatarSize.quote,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: SpaceTokens.s8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      l10n.resultQuote(line),
                      key: lineKey,
                      maxLines: _maxLines,
                      overflow: TextOverflow.ellipsis,
                      style: TypeTokens.quote.copyWith(color: ColorTokens.ink),
                    ),
                    Text(
                      l10n.lookLabel(quote.labelKey),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TypeTokens.label.copyWith(
                        color: ColorTokens.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return Padding(
      padding: EdgeInsets.only(top: gap),
      child: MediaQuery.disableAnimationsOf(context)
          ? card
          : TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: DesignExtras.resultFadeIn,
              curve: DesignExtras.resultFadeInCurve,
              builder: (context, opacity, child) =>
                  Opacity(opacity: opacity, child: child),
              child: card,
            ),
    );
  }
}

/// [quote]'s words in [trip], as the trip's bubble said them.
String? quoteLineOf(
  AppLocalizations l10n,
  ContentSource content,
  NumberFormatter numbers,
  Quote quote,
  TripDefinition trip,
) {
  final names = {
    for (final s in content.line(trip.lineId)?.stations ?? const <Never>[])
      s.stationId: s.name.arEg,
  };
  final slots = {for (final (i, s) in trip.stations.indexed) s.stationId: i};
  return SpeechResolver(
    pool: content.speechPool,
    piasters: numbers.piasters,
    station: (id) => names[id] ?? stationLetterOf(l10n, slots[id] ?? 0),
  ).resolve(
    speechKey: quote.speechKey,
    variant: quote.variant,
    amountPiasters: quote.amountPiasters,
    stationId: quote.stationId,
  );
}
