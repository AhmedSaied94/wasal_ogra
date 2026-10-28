import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/routing/router.dart';
import 'package:wassal/core/theme/components/system_bars.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/onboarding/domain/first_session.dart';
import 'package:wassal/features/onboarding/onboarding_providers.dart';
import 'package:wassal/features/onboarding/presentation/name_form.dart';
import 'package:wassal/features/onboarding/presentation/onboarding_card.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

/// The Name card, `/onboarding/name` (specs/012-m07-onboarding/contracts/
/// name.md "The Name card"), built to the `Name` artboard: a suggested name
/// already in the field, so one tap on «تمام» saves it and starts trip 1,
/// or goes to [then] when the playtest card gave one. Nothing waits for the
/// server; back does nothing.
class NameScreen extends ConsumerStatefulWidget {
  const NameScreen({this.then, super.key});

  /// Where to go after saving, as the link gave it (the playtest card's).
  final String? then;

  static const ctaKey = NameForm.ctaKey;
  static const diceKey = NameForm.diceKey;
  static const avatarKey = Key('NameScreen.avatar');

  @override
  ConsumerState<NameScreen> createState() => _NameScreenState();
}

class _NameScreenState extends ConsumerState<NameScreen> {
  @override
  void initState() {
    super.initState();
    // The first step of the session, when no opening scene wrote it.
    if (ref.read(tutorialPlanProvider).openingScene == null) {
      unawaited(
        ref.read(firstSessionFlagsProvider.notifier).reachStep(openingStep),
      );
    }
  }

  void _saved() {
    if (widget.then case final then?) {
      context.go(safeThen(then));
      return;
    }
    final trips = ref.read(tutorialPlanProvider).tutorialTrips;
    context.go(trips.isEmpty ? '/home' : '/trip/${trips.first}');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PopScope(
      canPop: false,
      child: SystemBars(
        bottom: ColorTokens.ground,
        child: Scaffold(
          backgroundColor: ColorTokens.ground,
          body: Stack(
            children: [
              const Positioned.fill(
                child: CustomPaint(painter: OnboardingCircles()),
              ),
              LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        LayoutTokens.gutter,
                        0,
                        LayoutTokens.gutter,
                        OnboardingCard.screenBottom,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [_card(l10n)],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _card(AppLocalizations l10n) => OnboardingCard(
    character: 'usta',
    avatarKey: NameScreen.avatarKey,
    children: [
      Text(
        l10n.nameTitle,
        textAlign: TextAlign.center,
        style: TypeTokens.displayL.copyWith(color: ColorTokens.ink),
      ),
      Text(
        l10n.nameSubtitle,
        textAlign: TextAlign.center,
        style: DesignExtras.nameSubtitle.copyWith(color: ColorTokens.inkMuted),
      ),
      NameForm(onSaved: _saved),
    ],
  );
}
