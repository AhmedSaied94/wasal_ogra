import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/economy/domain/op.dart';
import 'package:wassal/core/economy/domain/txn_id.dart';
import 'package:wassal/core/sync/domain/op_wire.dart';

// The wire of each operation type (specs/011-m06-identity-sync, contracts/
// sync.md "The wire").

final _id = TxnId.parse('0192f3a1-7b2c-7d4e-8f00-000000000001');

LedgerOp _op(OpType type, Map<String, Object> payload) => LedgerOp(
  seq: 7,
  op: Op(
    txnId: _id,
    type: type,
    payload: payload,
    occurredAtMs: DateTime.utc(
      2026,
      10,
      27,
      9,
      12,
      3,
      120,
    ).millisecondsSinceEpoch,
    contentVersion: 7,
    fuelMax: 5,
    fuelRegenMinutes: 20,
    jenehatDelta: -40,
    bonatDelta: 3,
    fuelDelta: -1,
    reason: LedgerReason.itemPurchase,
    ref: _id,
    maxEarningsJenehat: 90,
  ),
  syncStatus: SyncStatus.pending,
);

void main() {
  final payloads = <OpType, Map<String, Object>>{
    OpType.tripStart: {'trip_id': 'line_hay.05', 'fuel_mode': 'fuel'},
    OpType.tripResult: {'start_txn': _id.value, 'result': 'r'},
    OpType.adReward: {'placement': 'result_double', 'ref': _id.value},
    OpType.spendJenehat: {'kind': 'item', 'sku_id': 'salon.nish'},
    OpType.spendBonat: {'kind': 'booster', 'sku_id': 'change_bag'},
    OpType.useBooster: {'booster': 'change_bag', 'start_txn': _id.value},
    OpType.comebackGift: {},
    // M07 contracts/name.md and fuel-lesson.md: sent as stored.
    OpType.settingsUpdate: {'display_name': 'Hamada'},
    OpType.tutorialGift: {},
  };

  test('covers every operation type', () {
    expect(payloads.keys.toSet(), OpType.values.toSet());
  });

  for (final MapEntry(key: type, value: payload) in payloads.entries) {
    test('${type.wire} has the four fields and its payload', () {
      final wire = opWire(_op(type, payload));
      expect(wire.keys, ['client_txn_id', 'op_type', 'occurred_at', 'payload']);
      expect(wire['client_txn_id'], _id.value);
      expect(wire['op_type'], type.wire);
      final sent = wire['payload']! as Map<String, Object?>;
      if (contentVersionTypes.contains(type)) {
        expect(sent, {...payload, 'content_version': 7});
      } else {
        expect(sent, payload);
      }
    });
  }

  test('content_version only for trip_start and the two spends', () {
    expect(contentVersionTypes, {
      OpType.tripStart,
      OpType.spendJenehat,
      OpType.spendBonat,
    });
  });

  test('occurred_at is UTC with milliseconds and Z', () {
    final wire = opWire(_op(OpType.tripStart, payloads[OpType.tripStart]!));
    expect(wire['occurred_at'], '2026-10-27T09:12:03.120Z');
    final whole = opWire(
      LedgerOp(
        seq: 1,
        op: Op(
          txnId: _id,
          type: OpType.useBooster,
          payload: const {},
          occurredAtMs: DateTime.utc(2026, 10, 27).millisecondsSinceEpoch,
          contentVersion: 1,
          fuelMax: 5,
          fuelRegenMinutes: 20,
        ),
        syncStatus: SyncStatus.pending,
      ),
    );
    expect(whole['occurred_at'], '2026-10-27T00:00:00.000Z');
  });

  test('no local column leaks', () {
    for (final MapEntry(key: type, value: payload) in payloads.entries) {
      final text = jsonEncode(opWire(_op(type, payload)));
      for (final local in [
        'jenehat_delta',
        'bonat_delta',
        'fuel_delta',
        'fuel_max',
        'fuel_regen_minutes',
        'max_earnings_jenehat',
        'reason',
        'item_purchase',
        'seq',
        'sync_status',
      ]) {
        expect(text, isNot(contains(local)), reason: '${type.wire}: $local');
      }
    }
  });

  test('the stored payload is not changed', () {
    final payload = {'trip_id': 'line_hay.05', 'fuel_mode': 'fuel'};
    final op = _op(OpType.tripStart, payload);
    opWire(op);
    expect(op.op.payload, {'trip_id': 'line_hay.05', 'fuel_mode': 'fuel'});
  });
}
