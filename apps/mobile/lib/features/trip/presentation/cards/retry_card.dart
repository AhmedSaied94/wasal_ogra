// A save that failed on the device: a neutral message and «حاول تاني», which
// sends the same request again, so nothing is charged twice.
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/components/primary_button.dart';
import 'package:wassal/core/theme/components/secondary_button.dart';
import 'package:wassal/core/theme/tokens/space.dart';
import 'package:wassal/features/trip/application/trip_phase.dart';
import 'package:wassal/features/trip/presentation/cards/trip_card.dart';
import 'package:wassal/features/trip/presentation/trip_text.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

class RetryCard extends StatelessWidget {
  const RetryCard({
    required this.retry,
    required this.onRetry,
    this.onHome,
    super.key,
  });

  final TripRetry retry;
  final VoidCallback onRetry;

  /// Only before the trip has started.
  final VoidCallback? onHome;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final home = onHome;
    return TripCard(
      title: l10n.retryMessage(retry),
      children: [
        PrimaryButton(label: l10n.tripRetryAction, onPressed: onRetry),
        if (home != null) ...[
          const SizedBox(height: SpaceTokens.m),
          SecondaryButton(label: l10n.tripRetryHome, onPressed: home),
        ],
      ],
    );
  }
}
