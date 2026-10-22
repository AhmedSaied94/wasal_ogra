import 'package:uuid/data.dart';
import 'package:uuid/uuid.dart';
import 'package:wassal/core/economy/domain/txn_id.dart';

const _uuid = Uuid();

/// A new UUIDv7 stamped with [trustedMs], so ids sort roughly in the order
/// they were made (research R10).
TxnId newTxnId(int trustedMs) =>
    TxnId.parse(_uuid.v7(config: V7Options(trustedMs, null)));
