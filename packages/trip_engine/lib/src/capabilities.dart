// What the engine supports and says (content-contract.md §2). The same list
// is `content/engine/capabilities.json`, which content validation reads;
// `capabilities_test.dart` keeps the two equal.
import 'package:content_models/content_models.dart';

/// The 23 speech slots, in the file's order. A slot's default key is
/// `passenger.<slot>`, and a passenger's `speech_keys[slot]` overrides it.
enum SpeechSlot {
  pays('pays', {'amount'}),
  paysGroup('pays_group', {'amount'}),
  paysOldFare('pays_old_fare', {'amount'}),
  paysRest('pays_rest', {'amount'}),
  wantsChange('wants_change', {'amount'}),
  impatient('impatient', {}),
  thanks('thanks', {}),
  shortChange('short_change', {'amount'}),
  returnsExcess('returns_excess', {'amount'}),
  stopNear('stop_near', {'station'}),
  fight('fight', {'amount'}),
  missedStop('missed_stop', {'station'}),
  claimsPaid('claims_paid', {}),
  caught('caught', {}),
  accused('accused', {}),
  woke('woke', {}),
  attentive('attentive', {}),
  dropMeHere('drop_me_here', {}),
  dispute('dispute', {}),
  changeRequest('change_request', {'amount'}),
  changeRequestDeclined('change_request_declined', {}),
  boards('boards', {}),
  tip('tip', {'amount'});

  const SpeechSlot(this.wire, this.placeholders);

  final String wire;

  /// `amount` is filled from `PassengerSpeaks.amountPiasters`, and `station`
  /// from `PassengerSpeaks.stationId`.
  final Set<String> placeholders;

  String get defaultKey => 'passenger.$wire';

  bool get hasAmount => placeholders.contains('amount');

  bool get hasStation => placeholders.contains('station');
}

enum ParamUse { required, optional }

/// How one event parameter is checked. Any parameter an event doesn't list
/// is forbidden.
final class EventParamRule {
  const EventParamRule(
    this.use, {
    this.min,
    this.max,
    this.minItems,
    this.maxItems,
    this.oneOf,
    this.noGroupMembers = false,
  });

  final ParamUse use;
  final int? min;
  final int? max;
  final int? minItems;
  final int? maxItems;
  final List<int>? oneOf;

  /// The listed passengers may not have a `group_id`.
  final bool noGroupMembers;
}

abstract final class EngineCapabilities {
  static const int version = 1;

  /// The 12 supported archetypes (spec FR-004).
  static const Set<Archetype> archetypes = {
    Archetype.regular,
    Archetype.honest,
    Archetype.hajja,
    Archetype.sleeper,
    Archetype.hurry,
    Archetype.bigNote,
    Archetype.student,
    Archetype.headphones,
    Archetype.falseClaimer,
    Archetype.groupPayer,
    Archetype.chatty,
    Archetype.regularCustomer,
  };

  static const Set<EventId> events = {
    EventId.bump,
    EventId.traffic,
    EventId.openRoad,
    EventId.fareIncrease,
    EventId.dropMeHere,
    EventId.paymentDispute,
    EventId.changeRequest,
    EventId.roadsidePickup,
  };

  /// The notes a change request may ask for.
  static const List<int> changeRequestNotes = [1000, 2000, 5000, 10000, 20000];

  static const Map<EventId, Map<String, EventParamRule>> eventParams = {
    EventId.bump: {},
    EventId.traffic: {
      'seconds': EventParamRule(ParamUse.required, min: 1, max: 60),
    },
    EventId.openRoad: {
      'seconds': EventParamRule(ParamUse.required, min: 1, max: 60),
    },
    EventId.fareIncrease: {
      'amount_piasters': EventParamRule(ParamUse.required, min: 50),
      'passenger_ids': EventParamRule(
        ParamUse.optional,
        minItems: 1,
        maxItems: 6,
      ),
    },
    EventId.dropMeHere: {
      'passenger_ids': EventParamRule(
        ParamUse.required,
        minItems: 1,
        maxItems: 1,
      ),
      'seconds': EventParamRule(ParamUse.optional, min: 1, max: 60),
    },
    EventId.paymentDispute: {
      'passenger_ids': EventParamRule(
        ParamUse.required,
        minItems: 2,
        maxItems: 2,
        noGroupMembers: true,
      ),
    },
    EventId.changeRequest: {
      'passenger_ids': EventParamRule(
        ParamUse.required,
        minItems: 1,
        maxItems: 1,
      ),
      'amount_piasters': EventParamRule(
        ParamUse.required,
        oneOf: changeRequestNotes,
      ),
    },
    EventId.roadsidePickup: {
      'passenger_ids': EventParamRule(
        ParamUse.required,
        minItems: 1,
        maxItems: 6,
      ),
    },
  };

  static const List<SpeechSlot> speechSlots = SpeechSlot.values;
}
