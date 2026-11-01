// الشقة (specs/015-m10-apartment-story, contracts/apartment.md "The tab"):
// the goal view before chapter 4, the rooms view from it on. The rooms view
// itself is US2 (T062); until then it shows the tab's header and its own
// chapter bar.
import 'package:content_models/content_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/apartment/application/apartment_providers.dart';
import 'package:wassal/features/apartment/domain/apartment_view.dart';
import 'package:wassal/features/apartment/presentation/goal_view.dart';
import 'package:wassal/features/apartment/presentation/rooms_view.dart';
import 'package:wassal/features/home/application/start_next_trip.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

class ApartmentScreen extends ConsumerWidget {
  const ApartmentScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(apartmentViewProvider);
    return ColoredBox(
      color: ColorTokens.ground,
      child: switch (view) {
        GoalView(:final model) =>
          model == null
              ? const _NoGoal()
              : ApartmentGoalView(
                  model: model,
                  onBought: (chapter) => _startStoryTrip(context, ref, chapter),
                ),
        RoomsView(:final model, :final storyEnd) => ApartmentRoomsView(
          model: model,
          storyEnd: storyEnd,
        ),
      },
    );
  }
}

/// The card of [chapter]'s story trip, once its goal is bought (contracts/
/// apartment.md "The goal view"). A chapter with none changes nothing: the
/// view just rebuilds.
Future<void> _startStoryTrip(
  BuildContext context,
  WidgetRef ref,
  Chapter chapter,
) async {
  final trip = chapter.storyTripId;
  if (trip == null) return;
  // The purchase is stored, but what the progression rules read follows it
  // on the next turn of the event loop: until then the trip is still held
  // back by its chapter's goal.
  await Future<void>.delayed(Duration.zero);
  if (!context.mounted) return;
  await startNextTrip(context, ref, tripId: trip, from: StartFrom.apartment);
}

/// A pack with no chapter and no room: the title alone.
class _NoGoal extends StatelessWidget {
  const _NoGoal();

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Center(
      child: Text(
        AppLocalizations.of(context).apartmentTitle,
        style: TypeTokens.displayS,
      ),
    ),
  );
}
