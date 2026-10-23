// What a passenger looks like, from the content's `skin` slug (data-model.md
// "SkinLook"). The art ships in the app, so the table is app data. A label
// names what the player sees, never what the passenger does: a hidden
// behavior must not leak through it (research R10).
import 'package:content_models/content_models.dart';
import 'package:wassal/features/trip/domain/view_value.dart';

/// A shirt family; each has its own color token.
enum Shirt { effendi, student, worker, hajja, young, plain }

/// The Rive file's accessory values (contracts/rive-character.md).
enum Accessory { none, cap, glasses, headphones, tie, scarf, headscarf }

final class SkinLook extends ViewValue {
  const SkinLook({
    required this.skin,
    required this.shirt,
    required this.accessory,
    required this.labelKey,
  });

  /// The content's slug, such as `effendi_suit`.
  final String skin;
  final Shirt shirt;
  final Accessory accessory;

  /// The ARB key of the speaker label.
  final String labelKey;

  @override
  Map<String, Object?> get fields => {
    'skin': skin,
    'shirt': shirt,
    'accessory': accessory,
    'labelKey': labelKey,
  };
}

/// The neutral label of a skin the table doesn't know.
const passengerLabelKey = 'tripLookPassenger';

/// The label of a group payer in «آخر كلام».
const groupLabelKey = 'tripLookGroup';

/// Every skin the app has art for.
const skinLooks = <String, SkinLook>{
  'effendi_suit': SkinLook(
    skin: 'effendi_suit',
    shirt: Shirt.effendi,
    accessory: Accessory.none,
    labelKey: 'tripLookEffendi',
  ),
  'effendi_tie': SkinLook(
    skin: 'effendi_tie',
    shirt: Shirt.effendi,
    accessory: Accessory.tie,
    labelKey: 'tripLookEffendi',
  ),
  'student_cap': SkinLook(
    skin: 'student_cap',
    shirt: Shirt.student,
    accessory: Accessory.cap,
    labelKey: 'tripLookStudent',
  ),
  'worker_blue': SkinLook(
    skin: 'worker_blue',
    shirt: Shirt.worker,
    accessory: Accessory.none,
    labelKey: 'tripLookWorker',
  ),
  'hajja_black': SkinLook(
    skin: 'hajja_black',
    shirt: Shirt.hajja,
    accessory: Accessory.glasses,
    labelKey: 'tripLookHajja',
  ),
  'young_cap': SkinLook(
    skin: 'young_cap',
    shirt: Shirt.young,
    accessory: Accessory.cap,
    labelKey: 'tripLookYoung',
  ),
};

/// The look of [skin], or, for a skin the app has no art for, a look by
/// [archetype] with the neutral label. Archetypes whose behavior is hidden
/// fall back to the plain look, so the art gives nothing away.
SkinLook lookFor(String skin, Archetype archetype) =>
    skinLooks[skin] ?? _fallback(skin, archetype);

SkinLook _fallback(String skin, Archetype archetype) {
  final (shirt, accessory) = switch (archetype) {
    Archetype.hajja => (Shirt.hajja, Accessory.glasses),
    Archetype.student => (Shirt.student, Accessory.cap),
    Archetype.headphones => (Shirt.plain, Accessory.headphones),
    Archetype.sleeper => (Shirt.worker, Accessory.none),
    Archetype.hurry || Archetype.bigNote => (Shirt.effendi, Accessory.tie),
    _ => (Shirt.plain, Accessory.none),
  };
  return SkinLook(
    skin: skin,
    shirt: shirt,
    accessory: accessory,
    labelKey: passengerLabelKey,
  );
}

/// Pairs of shirts the table puts on passengers who otherwise look alike
/// (the same accessory). Their colors must differ in lightness, so the
/// palette test checks them.
List<(Shirt, Shirt)> shirtPairsToSeparate() {
  final byAccessory = <Accessory, Set<Shirt>>{};
  for (final look in skinLooks.values) {
    (byAccessory[look.accessory] ??= {}).add(look.shirt);
  }
  return [
    for (final shirts in byAccessory.values)
      for (final (i, a) in shirts.indexed)
        for (final b in shirts.skip(i + 1)) (a, b),
  ];
}
