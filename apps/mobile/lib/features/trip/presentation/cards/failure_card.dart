// The failure (ux-spec «فشل المشوار», FR-039, FR-040): «المشوار باظ», a
// line of what lost the reputation, the BONAT revive when the rules offer
// one (faded, with what is missing, when short), «عيد المشوار» with its
// liter and «ارجع الموقف». A revive whose save failed says so here, and
// the next tap sends the same request. The rewarded-ad revive is M11's.
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/economy/economy_providers.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/theme/components/primary_button.dart';
import 'package:wassal/core/theme/components/secondary_button.dart';
import 'package:wassal/core/theme/tokens/space.dart';
import 'package:wassal/features/trip/application/trip_phase.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';
import 'package:wassal/features/trip/presentation/cards/restart_button.dart';
import 'package:wassal/features/trip/presentation/cards/trip_card.dart';
import 'package:wassal/features/trip/presentation/trip_text.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

class FailureCard extends ConsumerWidget {
  const FailureCard({
    required this.summary,
    required this.retry,
    required this.restartEnabled,
    required this.onRevive,
    required this.onRestart,
    required this.onHome,
    super.key,
  });

  final FailSummary summary;

  /// A revive that failed to save, or null.
  final TripRetry? retry;
  final bool restartEnabled;
  final VoidCallback onRevive;
  final VoidCallback onRestart;
  final VoidCallback onHome;

  static const reviveKey = ValueKey('trip-fail-revive');
  static const restartKey = ValueKey('trip-fail-restart');
  static const homeKey = ValueKey('trip-fail-home');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final numbers = ref.watch(numberFormatterProvider);
    final causes = l10n.failCauses(summary, numbers);
    final revive = summary.revive;
    return TripCard(
      title: l10n.tripFailTitle,
      children: [
        if (causes.isNotEmpty) CardText(causes),
        if (retry case final retry?) CardText(l10n.retryMessage(retry)),
        if (revive != null) ...[
          Semantics(
            enabled: revive.affordable,
            child: Opacity(
              opacity: revive.affordable ? 1 : 0.55,
              child: PrimaryButton(
                key: reviveKey,
                label: l10n.tripFailRevive(numbers.integer(revive.priceBonat)),
                onPressed: revive.affordable ? onRevive : () {},
              ),
            ),
          ),
          if (!revive.affordable)
            CardNote(
              l10n.tripBoosterShort(
                numbers.integer(
                  math.max(
                    1,
                    revive.priceBonat - ref.watch(economyViewProvider).bonat,
                  ),
                ),
              ),
            ),
          const SizedBox(height: SpaceTokens.m),
        ],
        RestartButton(
          buttonKey: restartKey,
          enabled: restartEnabled,
          onRestart: onRestart,
        ),
        const SizedBox(height: SpaceTokens.m),
        SecondaryButton(key: homeKey, label: l10n.pauseHome, onPressed: onHome),
      ],
    );
  }
}
