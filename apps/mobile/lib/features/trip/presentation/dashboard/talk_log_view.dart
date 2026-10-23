// «آخر كلام» (FR-028): the last two lines said or received, newest at the
// bottom. A spoken rejection takes its place for two seconds.
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/theme/app_theme.dart';
import 'package:wassal/core/theme/tokens/typography.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';
import 'package:wassal/features/trip/presentation/trip_scope.dart';
import 'package:wassal/features/trip/presentation/trip_text.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

typedef _Talk = ({List<LogLine> lines, RejectionCode? rejection});

class TalkLogView extends ConsumerWidget {
  const TalkLogView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final numbers = ref.watch(numberFormatterProvider);
    final l10n = AppLocalizations.of(context);
    final style = TypeTokens.caption.copyWith(color: tokens.waraq, height: 1.2);
    return TripSelector<_Talk>(
      select: (model) => (
        lines: model.view?.log ?? const [],
        rejection: model.view?.rejection?.code,
      ),
      equals: (a, b) =>
          a.rejection == b.rejection && listEquals(a.lines, b.lines),
      builder: (context, talk) {
        final said = switch (talk.rejection) {
          final code? => l10n.rejection(code),
          null => null,
        };
        return Semantics(
          container: true,
          liveRegion: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                l10n.tripLogTitle,
                style: style.copyWith(color: tokens.shams),
              ),
              if (said != null)
                Text(
                  said,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: style.copyWith(
                    color: tokens.shams,
                    fontWeight: FontWeight.w700,
                    fontVariations: const [FontVariation('wght', 700)],
                  ),
                )
              else
                for (final line in talk.lines)
                  Text(
                    l10n.logLine(line, numbers),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: style,
                  ),
            ],
          ),
        );
      },
    );
  }
}
