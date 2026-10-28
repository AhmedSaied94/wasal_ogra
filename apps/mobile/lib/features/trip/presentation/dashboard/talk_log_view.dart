// «آخر كلام» (FR-028, HANDOFF §3.4 `LastWordsLog`, `C-Trip` boxes 93–94):
// the last two lines said or received, centred, the older one muted and the
// newest bold in white. A spoken rejection takes their place for two
// seconds. It is the trip's only live region.
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';
import 'package:wassal/features/trip/presentation/trip_scope.dart';
import 'package:wassal/features/trip/presentation/trip_text.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

typedef _Talk = ({List<LogLine> lines, RejectionCode? rejection});

class LastWordsLog extends ConsumerWidget {
  const LastWordsLog({this.oneLine = false, super.key});

  /// The compact dashboard's: the newest line only, 13/600 in
  /// `dashboard.text` (M07 contracts/compact-trip-layout.md).
  final bool oneLine;

  static final _oneLine = TypeTokens.caption
      .weight(600)
      .copyWith(color: ColorTokens.dashboardText, height: 1.3);

  static final _older = TypeTokens.caption
      .weight(500)
      .copyWith(color: ColorTokens.dashboardMuted, height: 1.3);
  static final _newest = TypeTokens.body
      .weight(700)
      .copyWith(color: ColorTokens.paper, height: 1.3);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final numbers = ref.watch(numberFormatterProvider);
    final l10n = AppLocalizations.of(context);
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
        final all = talk.lines;
        final lines = oneLine && all.isNotEmpty ? [all.last] : all;
        return Semantics(
          container: true,
          liveRegion: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (said != null)
                Text(
                  said,
                  maxLines: oneLine ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: (oneLine ? _oneLine : _older)
                      .weight(700)
                      .copyWith(color: ColorTokens.sun),
                )
              else
                for (final (i, line) in lines.indexed)
                  Text(
                    l10n.logLine(line, numbers),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: oneLine
                        ? _oneLine
                        : i == lines.length - 1
                        ? _newest
                        : _older,
                  ),
            ],
          ),
        );
      },
    );
  }
}
