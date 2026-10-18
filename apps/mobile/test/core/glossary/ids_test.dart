import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/glossary/ids.dart';

void main() {
  group('glossary §3.6 wire names', () {
    test('LineId matches the glossary exactly, in order', () {
      expect(LineId.values.map((v) => v.wireName), [
        'line_hay',
        'line_gamaa',
        'line_souq',
        'line_masyaf',
        'line_safar',
      ]);
    });

    test('VehicleId matches the glossary exactly, in order', () {
      expect(VehicleId.values.map((v) => v.wireName), [
        'tuktuk',
        'micro_old',
        'micro_new',
        'micro_safar',
      ]);
    });

    test('ChapterId matches the glossary exactly, in order', () {
      expect(ChapterId.values.map((v) => v.wireName), [
        'ch1_first_job',
        'ch2_her_father',
        'ch3_shabka',
        'ch4_salon',
        'ch5_kitchen',
        'ch6_bedroom',
        'ch7_wedding',
      ]);
    });

    test('RoomId matches the glossary exactly, in order', () {
      expect(RoomId.values.map((v) => v.wireName), [
        'salon',
        'kitchen',
        'bedroom',
      ]);
    });
  });

  group('fromWire', () {
    test('round-trips every known value', () {
      for (final v in LineId.values) {
        expect(LineId.fromWire(v.wireName), v);
      }
      for (final v in VehicleId.values) {
        expect(VehicleId.fromWire(v.wireName), v);
      }
      for (final v in ChapterId.values) {
        expect(ChapterId.fromWire(v.wireName), v);
      }
      for (final v in RoomId.values) {
        expect(RoomId.fromWire(v.wireName), v);
      }
    });

    test('returns null for unknown or differently cased strings', () {
      expect(LineId.fromWire('line_xyz'), isNull);
      expect(LineId.fromWire('LINE_HAY'), isNull);
      expect(VehicleId.fromWire(''), isNull);
      expect(ChapterId.fromWire('ch8_honeymoon'), isNull);
      expect(RoomId.fromWire('bathroom'), isNull);
    });
  });
}
