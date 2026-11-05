// «كمّل» on the result (specs/012-m07-onboarding/contracts/first-session.md
// "The result screen", until M08): through the first session, and once after
// the trip that ends it, the result's way on to the next tutorial trip or to
// الموقف. The way on to a trip passes Home's between-trips checkpoint first,
// where M11 starts the ads before tutorial trip 3 (specs/018-m11-ads,
// analysis U1).
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/content/content_providers.dart';
import 'package:wassal/core/progress/application/player_progress_provider.dart';
import 'package:wassal/core/progress/domain/playable.dart';
import 'package:wassal/core/theme/components/buttons.dart';
import 'package:wassal/features/home/application/checkpoint.dart';
import 'package:wassal/features/onboarding/onboarding_providers.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

class FirstSessionContinue extends ConsumerWidget {
  const FirstSessionContinue({required this.tripId, super.key});

  /// The trip whose result this is.
  final String tripId;

  static const buttonKey = ValueKey('first-session-continue');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(firstSessionProvider);
    final endedHere = ref.watch(tutorialEndedOnProvider) == tripId;
    if (!session.inFirstSession && !endedHere) return const SizedBox.shrink();
    return AppButton.primary(
      key: buttonKey,
      label: AppLocalizations.of(context).firstSessionContinue,
      size: AppButtonSize.l,
      onTap: () => unawaited(_continue(context, ref, endedHere: endedHere)),
    );
  }

  Future<void> _continue(
    BuildContext context,
    WidgetRef ref, {
    required bool endedHere,
  }) async {
    if (endedHere) ref.read(tutorialEndedOnProvider.notifier).tripId = null;
    final content = ref.read(contentSourceProvider);
    final progress = ref.read(playerProgressProvider);
    final next = ref
        .read(firstSessionProvider)
        .nextAfterResult(
          tripId,
          playable: (id) => tripPlayable(content, progress, id),
        );
    if (next.startsWith('/trip/')) {
      await ref.read(betweenTripsCheckpointProvider).pass();
      if (!context.mounted) return;
    }
    context.go(next);
  }
}
