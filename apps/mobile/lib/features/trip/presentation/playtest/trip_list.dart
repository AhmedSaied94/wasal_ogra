// Internal builds' trip list (research R21): every trip of the active
// pack, by line, on Home's placeholder; each opens its trip, and the
// tutorial's are marked with their place in it (M07). Prod never builds it
// (router.dart).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/content/content_providers.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/routing/nav_guard.dart';
import 'package:wassal/core/theme/components/buttons.dart';
import 'package:wassal/core/theme/components/pills.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/onboarding/onboarding_providers.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

class TripList extends ConsumerWidget {
  const TripList({super.key});

  static Key tripKey(String tripId) => ValueKey('trip-list-$tripId');
  static Key tutorialKey(String tripId) =>
      ValueKey('trip-list-tutorial-$tripId');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final content = ref.watch(contentSourceProvider);
    final numbers = ref.watch(numberFormatterProvider);
    final tutorial = ref.watch(tutorialPlanProvider).tutorialTrips;
    final lines = [...content.lines]
      ..sort((a, b) => a.order.compareTo(b.order));
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: SpaceTokens.s8,
      children: [
        Semantics(
          header: true,
          child: Text(
            l10n.tripPlaytestTrips,
            style: TypeTokens.displayS.copyWith(color: ColorTokens.ink),
          ),
        ),
        for (final line in lines)
          if (content.tripsOf(line.lineId) case final trips
              when trips.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(top: SpaceTokens.s8),
              child: Text(
                line.name.arEg,
                style: TypeTokens.label.copyWith(color: ColorTokens.ink2),
              ),
            ),
            for (final trip in trips)
              Row(
                spacing: SpaceTokens.s8,
                children: [
                  Expanded(
                    child: AppButton.secondary(
                      key: tripKey(trip.tripId),
                      // A Latin id.
                      label: trip.tripId,
                      size: AppButtonSize.compact,
                      onTap: () => NavGuard.go(context, '/trip/${trip.tripId}'),
                    ),
                  ),
                  if (tutorial.indexOf(trip.tripId) case final i when i >= 0)
                    StatusChip.new_(
                      key: tutorialKey(trip.tripId),
                      label: l10n.tripPlaytestTutorial(numbers.integer(i + 1)),
                    ),
                ],
              ),
          ],
      ],
    );
  }
}
