// The card's «جديد» (specs/013-m08-home-result, `PreTrip` boxes 29–34,
// FR-029, research R5): the type's face or the event's icon on a 60 pt
// circle, the chip, the name and what the engine does with it.
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/components/app_icon.dart';
import 'package:wassal/core/theme/components/avatars.dart';
import 'package:wassal/core/theme/components/pills.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/pre_trip/domain/briefing.dart';
import 'package:wassal/features/pre_trip/domain/new_subjects.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

/// [subject]'s name and sentence, looked up by their ARB keys.
({String name, String text}) newCardStrings(
  AppLocalizations l10n,
  NewSubject subject,
) => (
  name: _lookup(l10n, newCardNameKey(subject.wire)),
  text: _lookup(l10n, newCardTextKey(subject.wire)),
);

class NewCard extends StatelessWidget {
  const NewCard({required this.subject, super.key});

  final NewSubject subject;

  static const double _circle = 60;
  static const double _eventIcon = 34;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final (:name, :text) = newCardStrings(l10n, subject);
    return Semantics(
      container: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: SpaceTokens.s12,
          vertical: SpaceTokens.s10,
        ),
        decoration: BoxDecoration(
          color: ColorTokens.sunSoft,
          borderRadius: BorderRadius.circular(RadiusTokens.l),
        ),
        child: Row(
          spacing: SpaceTokens.s12,
          children: [
            switch (subject) {
              NewArchetype(:final look) => PassengerAvatar(
                lookId: look.id,
                person: look.rive,
                size: PassengerAvatarSize.newCard,
              ),
              NewEvent(:final icon) => Container(
                width: _circle,
                height: _circle,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: ColorTokens.paper,
                  shape: BoxShape.circle,
                ),
                child: AppIcon(icon, size: _eventIcon),
              ),
            },
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: SpaceTokens.s2,
                children: [
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: SpaceTokens.s6,
                    children: [
                      StatusChip.new_(label: l10n.preTripNew),
                      Text(
                        name,
                        style: DesignExtras.newCardName.copyWith(
                          color: ColorTokens.ink,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    text,
                    style: DesignExtras.newCardText.copyWith(
                      color: ColorTokens.ink,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _lookup(AppLocalizations l10n, String key) => switch (key) {
  'newCardHonest' => l10n.newCardHonest,
  'newCardHonestText' => l10n.newCardHonestText,
  'newCardHajja' => l10n.newCardHajja,
  'newCardHajjaText' => l10n.newCardHajjaText,
  'newCardSleeper' => l10n.newCardSleeper,
  'newCardSleeperText' => l10n.newCardSleeperText,
  'newCardHurry' => l10n.newCardHurry,
  'newCardHurryText' => l10n.newCardHurryText,
  'newCardBigNote' => l10n.newCardBigNote,
  'newCardBigNoteText' => l10n.newCardBigNoteText,
  'newCardStudent' => l10n.newCardStudent,
  'newCardStudentText' => l10n.newCardStudentText,
  'newCardHeadphones' => l10n.newCardHeadphones,
  'newCardHeadphonesText' => l10n.newCardHeadphonesText,
  'newCardFalseClaimer' => l10n.newCardFalseClaimer,
  'newCardFalseClaimerText' => l10n.newCardFalseClaimerText,
  'newCardGroupPayer' => l10n.newCardGroupPayer,
  'newCardGroupPayerText' => l10n.newCardGroupPayerText,
  'newCardChatty' => l10n.newCardChatty,
  'newCardChattyText' => l10n.newCardChattyText,
  'newCardRegularCustomer' => l10n.newCardRegularCustomer,
  'newCardRegularCustomerText' => l10n.newCardRegularCustomerText,
  'newCardBump' => l10n.newCardBump,
  'newCardBumpText' => l10n.newCardBumpText,
  'newCardTraffic' => l10n.newCardTraffic,
  'newCardTrafficText' => l10n.newCardTrafficText,
  'newCardOpenRoad' => l10n.newCardOpenRoad,
  'newCardOpenRoadText' => l10n.newCardOpenRoadText,
  'newCardFareIncrease' => l10n.newCardFareIncrease,
  'newCardFareIncreaseText' => l10n.newCardFareIncreaseText,
  'newCardDropMeHere' => l10n.newCardDropMeHere,
  'newCardDropMeHereText' => l10n.newCardDropMeHereText,
  'newCardPaymentDispute' => l10n.newCardPaymentDispute,
  'newCardPaymentDisputeText' => l10n.newCardPaymentDisputeText,
  'newCardChangeRequest' => l10n.newCardChangeRequest,
  'newCardChangeRequestText' => l10n.newCardChangeRequestText,
  'newCardRoadsidePickup' => l10n.newCardRoadsidePickup,
  'newCardRoadsidePickupText' => l10n.newCardRoadsidePickupText,
  _ => throw ArgumentError.value(key, 'key', 'no new-card string'),
};
