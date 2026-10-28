// Internal builds' «Onboarding» card (specs/012-m07-onboarding, US6,
// research R21): the first session's screens on demand, each back to Home,
// and "coach on every tutorial trip", held in memory. It sits under the
// playtest Home's links, above the sync card, so the links stay where they
// were. Prod never builds it (router.dart).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/routing/nav_guard.dart';
import 'package:wassal/core/theme/components/buttons.dart';
import 'package:wassal/core/theme/components/containers.dart';
import 'package:wassal/core/theme/components/controls.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/onboarding/onboarding_providers.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

class OnboardingCard extends ConsumerWidget {
  const OnboardingCard({super.key});

  static const openingKey = ValueKey('onboarding-playtest-opening');
  static const nameKey = ValueKey('onboarding-playtest-name');
  static const fuelKey = ValueKey('onboarding-playtest-fuel');
  static const coachEverywhereKey = ValueKey('onboarding-playtest-coach');
  static Key sceneKey(String sceneId) =>
      ValueKey('onboarding-playtest-scene-$sceneId');

  /// [path] with `then=/home`, so the screen comes back to Home.
  static String _thenHome(String path) =>
      Uri(path: path, queryParameters: {'then': '/home'}).toString();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final plan = ref.watch(tutorialPlanProvider);
    final coach = ref.watch(coachEverywhereProvider);
    Widget open(Key key, String label, String location) => AppButton.secondary(
      key: key,
      label: label,
      size: AppButtonSize.compact,
      onTap: () => NavGuard.go(context, location),
    );
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: SpaceTokens.s8,
        children: [
          Semantics(
            header: true,
            child: Text(
              l10n.onboardingPlaytestTitle,
              style: TypeTokens.displayS.copyWith(color: ColorTokens.ink),
            ),
          ),
          if (plan.openingScene != null)
            open(
              openingKey,
              l10n.onboardingPlaytestOpening,
              _thenHome('/onboarding/intro'),
            ),
          open(
            nameKey,
            l10n.onboardingPlaytestName,
            _thenHome('/onboarding/name'),
          ),
          for (final scene in {...plan.afterTripScenes.values})
            open(
              sceneKey(scene),
              l10n.onboardingPlaytestScene(scene),
              _thenHome('/onboarding/scene/$scene'),
            ),
          // Without a trip to start, the lesson goes back to Home.
          open(fuelKey, l10n.onboardingPlaytestFuel, '/onboarding/fuel'),
          AppSwitch(
            key: coachEverywhereKey,
            label: l10n.onboardingPlaytestCoach,
            value: coach,
            onChanged: (on) =>
                ref.read(coachEverywhereProvider.notifier).on = on,
          ),
        ],
      ),
    );
  }
}
