// Internal builds' trip list (research R21): every trip of the active
// pack, by line, on Home's placeholder; each opens its trip. Prod never
// builds it (router.dart).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/content/content_providers.dart';
import 'package:wassal/core/routing/nav_guard.dart';
import 'package:wassal/core/theme/app_theme.dart';
import 'package:wassal/core/theme/components/secondary_button.dart';
import 'package:wassal/core/theme/tokens/space.dart';
import 'package:wassal/core/theme/tokens/typography.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

class TripList extends ConsumerWidget {
  const TripList({super.key});

  static Key tripKey(String tripId) => ValueKey('trip-list-$tripId');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final ink = context.tokens.hibr;
    final content = ref.watch(contentSourceProvider);
    final lines = [...content.lines]
      ..sort((a, b) => a.order.compareTo(b.order));
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            l10n.tripPlaytestTrips,
            style: TypeTokens.title.copyWith(color: ink),
          ),
        ),
        for (final line in lines)
          if (content.tripsOf(line.lineId) case final trips
              when trips.isNotEmpty) ...[
            const SizedBox(height: SpaceTokens.m),
            Text(line.name.arEg, style: TypeTokens.label.copyWith(color: ink)),
            for (final trip in trips) ...[
              const SizedBox(height: SpaceTokens.s),
              SecondaryButton(
                key: tripKey(trip.tripId),
                // A Latin id.
                label: trip.tripId,
                onPressed: () => NavGuard.go(context, '/trip/${trip.tripId}'),
              ),
            ],
          ],
      ],
    );
  }
}
