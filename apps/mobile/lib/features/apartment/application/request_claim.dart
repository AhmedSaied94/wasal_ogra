// Taking a family request's reward (specs/015-m10-apartment-story, contracts/
// apartment.md "Family requests", research R11): rules first, then one
// request id held per request, as `GoalPurchase`. The BONAT is the server's
// (constitution IV): a claim only records the request, and the reward stays
// pending until M06's sync brings the answer.
import 'package:content_models/content_models.dart';
import 'package:wassal/core/content/domain/content_source.dart';
import 'package:wassal/core/economy/economy.dart';
import 'package:wassal/core/progress/domain/player_progress.dart';
import 'package:wassal/core/progress/domain/requests.dart';

/// What a claim did.
sealed class RequestClaimResult {
  const RequestClaimResult();
}

/// The rules refused it, or a call for this request is in flight: nothing
/// was sent.
final class RequestNotAllowed extends RequestClaimResult {
  const RequestNotAllowed();
}

final class RequestClaimed extends RequestClaimResult {
  const RequestClaimed();
}

/// The phone's economy refused it (`not_eligible`, `already_granted`, …).
/// The request stays in the list as it was.
final class RequestRefused extends RequestClaimResult {
  const RequestRefused(this.code);

  final EconomyRefusal code;
}

/// The write failed: the held id stays for the next tap.
final class RequestWriteFailed extends RequestClaimResult {
  const RequestWriteFailed();
}

final class RequestClaim {
  RequestClaim(this._economy, this._content);

  final Economy _economy;
  final ContentSource _content;
  final _ids = <String, TxnId>{};
  final _busy = <String>{};

  /// A call for [requestId] is in flight.
  bool busyWith(String requestId) => _busy.contains(requestId);

  /// Takes [request]'s reward. The caller passes what the screen shows, so a
  /// stale tap after a sync is judged on the rules, never on the old list.
  Future<RequestClaimResult> claim(
    FamilyRequest request, {
    required PlayerProgress progress,
    required String? Function(String itemId) variantOf,
    required Set<String> requestsClaimed,
  }) async {
    final requestId = request.requestId;
    if (_busy.contains(requestId) ||
        requestState(_content, progress, request, variantOf, requestsClaimed) !=
            RequestState.done) {
      return const RequestNotAllowed();
    }
    _busy.add(requestId);
    try {
      final id = _ids[requestId] ??= _economy.newRequestId();
      final outcome = await _economy.claimRequest(id, requestId: requestId);
      switch (outcome) {
        case OpApplied():
          _ids.remove(requestId);
          return const RequestClaimed();
        case OpRefused(:final code):
          _ids.remove(requestId);
          return RequestRefused(code);
        case OpWriteFailed():
          return const RequestWriteFailed();
      }
    } finally {
      _busy.remove(requestId);
    }
  }
}
