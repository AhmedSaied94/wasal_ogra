// A client transaction id (specs/007-m05-local-economy/research.md R10).

final _uuidV7 = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

/// A UUIDv7 in canonical lowercase form: the `client_txn_id` of one player
/// intent. Anything else is refused, so a stored id is always one the server
/// accepts.
final class TxnId {
  const TxnId._(this.value);

  /// Throws [FormatException] unless [value] is a lowercase UUIDv7.
  factory TxnId.parse(String value) {
    if (!_uuidV7.hasMatch(value)) {
      throw FormatException('not a lowercase UUIDv7', value);
    }
    return TxnId._(value);
  }

  final String value;

  @override
  bool operator ==(Object other) => other is TxnId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}
