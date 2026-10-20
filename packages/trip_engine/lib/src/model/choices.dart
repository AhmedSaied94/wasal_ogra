// The open choices and small records of a trip (data-model.md "Open
// choices").

/// An open claim, keyed by passenger.
final class Claim {
  const Claim({required this.truthful});

  /// True when the passenger really sent their fare.
  final bool truthful;

  Map<String, Object> toJson() => {'truthful': truthful};
}

/// An open payment dispute, keyed by its event index.
final class Dispute {
  const Dispute({required this.a, required this.b});

  final String a;
  final String b;

  Map<String, Object> toJson() => {'a': a, 'b': b};
}

/// An open change request, keyed by passenger.
final class ChangeRequest {
  const ChangeRequest({required this.notePiasters});

  final int notePiasters;

  Map<String, Object> toJson() => {'note_piasters': notePiasters};
}

/// A «حد معاه فكة؟» request that hasn't completed.
final class PendingBreak {
  const PendingBreak({required this.denomination, required this.completesAtMs});

  final int denomination;
  final int completesAtMs;

  Map<String, Object> toJson() => {
    'denomination': denomination,
    'completes_at_ms': completesAtMs,
  };
}

/// The last `SendHand`, for undo.
final class LastSend {
  const LastSend({required this.tokenId, required this.untilMs});

  final int tokenId;
  final int untilMs;

  Map<String, Object> toJson() => {'token_id': tokenId, 'until_ms': untilMs};
}
