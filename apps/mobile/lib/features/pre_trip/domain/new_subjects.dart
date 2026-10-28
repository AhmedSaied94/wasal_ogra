// What the pre-trip card's «جديد» can introduce (specs/013-m08-home-result,
// research R5): a closed table, checked against the engine's capabilities
// and the ARB, so a new archetype can't ship without its sentence.
import 'package:content_models/content_models.dart';

/// Every archetype the engine supports but `regular`, the baseline, by
/// wire id.
const newCardArchetypes = <Archetype, String>{
  Archetype.honest: 'honest',
  Archetype.hajja: 'hajja',
  Archetype.sleeper: 'sleeper',
  Archetype.hurry: 'hurry',
  Archetype.bigNote: 'big_note',
  Archetype.student: 'student',
  Archetype.headphones: 'headphones',
  Archetype.falseClaimer: 'false_claimer',
  Archetype.groupPayer: 'group_payer',
  Archetype.chatty: 'chatty',
  Archetype.regularCustomer: 'regular_customer',
};

/// The eight in-trip events, by wire id.
const newCardEvents = <EventId, String>{
  EventId.bump: 'bump',
  EventId.traffic: 'traffic',
  EventId.openRoad: 'open_road',
  EventId.fareIncrease: 'fare_increase',
  EventId.dropMeHere: 'drop_me_here',
  EventId.paymentDispute: 'payment_dispute',
  EventId.changeRequest: 'change_request',
  EventId.roadsidePickup: 'roadside_pickup',
};

/// Both tables' wire ids.
final newCardSubjects = {...newCardArchetypes.values, ...newCardEvents.values};

/// The ARB keys of a subject's name and sentence: `big_note` →
/// `newCardBigNote`, `newCardBigNoteText`.
String newCardNameKey(String wire) => 'newCard${_pascal(wire)}';
String newCardTextKey(String wire) => '${newCardNameKey(wire)}Text';

String _pascal(String wire) => [
  for (final word in wire.split('_'))
    '${word[0].toUpperCase()}${word.substring(1)}',
].join();

/// The design has no event glyphs: the nearest icon for each.
const eventIcons = <EventId, String>{
  EventId.bump: 'warning',
  EventId.traffic: 'booster_traffic',
  EventId.openRoad: 'route_bold',
  EventId.fareIncrease: 'coin_up',
  EventId.dropMeHere: 'hand',
  EventId.paymentDispute: 'speech',
  EventId.changeRequest: 'call_change',
  EventId.roadsidePickup: 'hand',
};

/// The archetypes that carry a bag or a child (FR-028). No engine
/// archetype does yet (RULES §6.1), so the bag and child lines stay off
/// until one does.
const bagArchetypes = <Archetype>{};
const childArchetypes = <Archetype>{};
