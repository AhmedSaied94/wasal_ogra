// The engine and content/engine/capabilities.json agree (content-contract.md
// §2): what content may use is exactly what the engine supports.
import 'dart:convert';
import 'dart:io';

import 'package:content_models/content_models.dart';
import 'package:test/test.dart';
import 'package:trip_engine/src/wire.dart';
import 'package:trip_engine/trip_engine.dart';

final _file = jsonDecode(
  File('../../content/engine/capabilities.json').readAsStringSync(),
) as Map<String, Object?>;

Map<String, Object> _ruleJson(EventParamRule rule) => {
  'use': rule.use.name,
  'min': ?rule.min,
  'max': ?rule.max,
  'min_items': ?rule.minItems,
  'max_items': ?rule.maxItems,
  if (rule.noGroupMembers) 'no_group_members': true,
  'one_of': ?rule.oneOf,
};

void main() {
  test('the file version is 1', () {
    expect(_file['version'], EngineCapabilities.version);
  });

  test('archetypes', () {
    expect(
      EngineCapabilities.archetypes.map(wireName).toList(),
      _file['archetypes'],
    );
    expect(EngineCapabilities.archetypes, hasLength(12));
  });

  test('events and their parameter rules', () {
    final events = _file['events']! as Map<String, Object?>;
    expect(
      EngineCapabilities.events.map(wireName).toList(),
      events.keys.toList(),
    );
    expect(EngineCapabilities.events.toSet(), EventId.values.toSet());
    for (final event in EngineCapabilities.events) {
      final rules = EngineCapabilities.eventParams[event]!;
      expect(
        {
          for (final MapEntry(:key, :value) in rules.entries)
            key: _ruleJson(value),
        },
        events[wireName(event)],
        reason: wireName(event),
      );
    }
  });

  test('speech slots: wire names, order, placeholders and default keys', () {
    final slots = (_file['speech_slots']! as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(EngineCapabilities.speechSlots, SpeechSlot.values);
    expect(SpeechSlot.values.map((slot) => slot.wire).toList(), [
      for (final slot in slots) slot['slot'],
    ]);
    for (final (index, slot) in SpeechSlot.values.indexed) {
      expect(
        slot.placeholders.toList(),
        slots[index]['placeholders'],
        reason: slot.wire,
      );
      expect(slot.defaultKey, 'passenger.${slot.wire}');
    }
    expect(SpeechSlot.values, hasLength(23));
  });

  test('change-request notes', () {
    final events = _file['events']! as Map<String, Object?>;
    final request =
        (events['change_request']! as Map<String, Object?>)['amount_piasters']!
            as Map<String, Object?>;
    expect(EngineCapabilities.changeRequestNotes, request['one_of']);
  });

  test('wire names follow the schemas', () {
    final common = jsonDecode(
      File('../../content/schemas/common.schema.json').readAsStringSync(),
    ) as Map<String, Object?>;
    final defs = common[r'$defs']! as Map<String, Object?>;
    List<Object?> enumOf(String name) =>
        (defs[name]! as Map<String, Object?>)['enum']! as List<Object?>;
    expect(Archetype.values.map(wireName).toList(), enumOf('Archetype'));
    expect(BoosterId.values.map(wireName).toList(), enumOf('BoosterId'));
    expect(EventId.values.map(wireName).toList(), enumOf('EventId'));
    expect(LineId.values.map(wireName).toList(), enumOf('LineId'));
    expect(VehicleId.values.map(wireName).toList(), enumOf('VehicleId'));
    expect(
      Denomination.values.map(denominationValue).toList(),
      enumOf('Denomination'),
    );
    expect(
      byWire(BoosterId.values, 'fuel_unlimited_1h'),
      BoosterId.fuelUnlimited1h,
    );
    expect(byWire(BoosterId.values, 'nope'), isNull);
    expect(denominationOf(500), Denomination.v500);
    expect(denominationOf(300), isNull);
  });
}
