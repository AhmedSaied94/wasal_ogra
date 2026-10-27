// `POST /v1/sync`'s answer (B03 contracts/api.md): one result per
// operation, in order, and the wallet after the batch.
import 'package:wassal/core/sync/domain/wire/reader.dart';
import 'package:wassal/core/sync/domain/wire/server_wallet.dart';

/// One operation's result. A `reason` the app doesn't know is a plain
/// rejection (research R10).
final class OpResult {
  const OpResult.accepted(this.txnId, {this.granted}) : reason = null;

  const OpResult.rejected(this.txnId, String this.reason) : granted = null;

  final String txnId;

  /// Null when accepted.
  final String? reason;

  /// What the server granted beyond the operation itself. Read only for the
  /// debug card: the answer's wallet already counts it (research R10).
  final List<Object?>? granted;

  bool get accepted => reason == null;

  @override
  String toString() => accepted ? 'accepted $txnId' : 'rejected $txnId $reason';
}

final class SyncAnswer {
  const SyncAnswer({
    required this.stateVersion,
    required this.stateStale,
    required this.results,
    required this.wallet,
  });

  factory SyncAnswer.fromJson(Object? json) {
    final o = WireObject.of(json);
    return SyncAnswer(
      stateVersion: o.integer('state_version'),
      stateStale: o.boolean('state_stale'),
      results: [
        for (final row in o.objects('results'))
          switch (row.string('status')) {
            'accepted' => OpResult.accepted(
              row.string('client_txn_id'),
              granted: row.has('granted') ? row.list('granted') : null,
            ),
            'rejected' => OpResult.rejected(
              row.string('client_txn_id'),
              row.optionalString('reason') ?? 'unknown',
            ),
            final status => throw WireFormatException(
              'unknown result status $status',
            ),
          },
      ],
      wallet: ServerWallet.fromJson(o.raw['wallet']),
    );
  }

  final int stateVersion;

  /// The batch was validated against a state another phone or staff changed
  /// since this phone's base: the full state follows (research R11, R12).
  final bool stateStale;
  final List<OpResult> results;
  final ServerWallet wallet;
}
