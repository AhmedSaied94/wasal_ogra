// What a passenger looks like, from the content's `skin` slug
// (specs/008.5-m21-design-refresh, data-model.md "Looks"). The art ships in
// the app, so the table is app data. A label names what the player sees,
// never what the passenger does: a hidden behaviour must not leak through
// it (M02 research R10).
import 'package:content_models/content_models.dart';
import 'package:wassal/features/trip/domain/view_value.dart';

final class Look extends ViewValue {
  const Look({required this.id, required this.labelKey, required this.rive});

  /// The design's art id (HANDOFF §5.3), such as `hagga`.
  final String id;

  /// The ARB key of the speaker label.
  final String labelKey;

  /// Its `look` number in `wassal.riv`'s `Person` artboard
  /// (contracts/rive-characters.md "Looks").
  final int rive;

  /// The static art, drawn when Rive isn't.
  String get svg => 'assets/illustrations/passengers/$id.svg';

  @override
  Map<String, Object?> get fields => {
    'id': id,
    'labelKey': labelKey,
    'rive': rive,
  };
}

/// The neutral label: a look nothing about which may be named.
const passengerLabelKey = 'tripLookPassenger';

/// The label of a group payer in «آخر كلام».
const groupLabelKey = 'tripLookGroup';

/// The MVP's twelve looks, in the design's order.
const looks = <String, Look>{
  'regular': Look(id: 'regular', labelKey: passengerLabelKey, rive: 0),
  'hagga': Look(id: 'hagga', labelKey: 'tripLookHajja', rive: 1),
  'sleeper': Look(id: 'sleeper', labelKey: passengerLabelKey, rive: 2),
  'effendi_200': Look(id: 'effendi_200', labelKey: 'tripLookEffendi', rive: 4),
  'student': Look(id: 'student', labelKey: 'tripLookStudent', rive: 5),
  'headphones': Look(id: 'headphones', labelKey: 'tripLookHeadphones', rive: 6),
  'hurried': Look(id: 'hurried', labelKey: passengerLabelKey, rive: 3),
  'claimer': Look(id: 'claimer', labelKey: passengerLabelKey, rive: 7),
  'group_payer': Look(id: 'group_payer', labelKey: passengerLabelKey, rive: 8),
  'chatterbox': Look(id: 'chatterbox', labelKey: passengerLabelKey, rive: 9),
  'regular_customer': Look(
    id: 'regular_customer',
    labelKey: passengerLabelKey,
    rive: 16,
  ),
  'honest': Look(id: 'honest', labelKey: passengerLabelKey, rive: 17),
};

/// The sample pack's skins, before the design named its looks.
const skinAliases = <String, String>{
  'effendi_suit': 'effendi_200',
  'effendi_tie': 'effendi_200',
  'hajja_black': 'hagga',
  'student_cap': 'student',
  'worker_blue': 'regular',
  'young_cap': 'group_payer',
};

/// The look of [skin]: a look id, an alias, or, for a skin the app has no
/// art for, a look by [archetype] with the neutral label. Archetypes whose
/// behaviour is hidden fall back to `regular`, so the art gives nothing
/// away.
Look lookFor(String skin, Archetype archetype) =>
    looks[skin] ?? looks[skinAliases[skin]] ?? _fallback(archetype);

Look _fallback(Archetype archetype) {
  final look =
      looks[switch (archetype) {
        Archetype.hajja => 'hagga',
        Archetype.student => 'student',
        Archetype.headphones => 'headphones',
        Archetype.sleeper => 'sleeper',
        Archetype.hurry => 'hurried',
        Archetype.bigNote => 'effendi_200',
        _ => 'regular',
      }]!;
  return Look(id: look.id, labelKey: passengerLabelKey, rive: look.rive);
}
