// The player endpoints with the session's token (specs/011-m06-identity-
// sync, contracts/api-client.md "`AuthorizedApi`", research R4): renewal
// before a token runs out, one renewal at a time, the retry window of a
// lost renewal, the repeat after a `401`, and signing in again when the
// session can't be saved. Tokens are stored before anything uses them, and
// never logged.
import 'dart:async';

import 'package:flutter/services.dart' show PlatformException;

import 'package:wassal/core/account/domain/account.dart';
import 'package:wassal/core/account/session_store.dart';
import 'package:wassal/core/network/api_client.dart';
import 'package:wassal/core/sync/domain/wire/reader.dart';
import 'package:wassal/core/sync/domain/wire/token_pair.dart';

abstract interface class AuthorizedApi {
  /// Sends [request] with the session's access token. Renews before it when
  /// the access has under 60 s left, and handles the 401s of research R4.
  /// Answers `ApiFailure(403, 'account_deleted')` without a request when the
  /// account is deleted.
  Future<ApiResult> send(ApiRequest request);
}

/// Renew when the access token has less than this left (B02).
const renewMargin = Duration(seconds: 60);

/// A lost renewal is retried with the same refresh token while the first
/// attempt is this recent (B02's retry window)…
const renewRetryWindow = Duration(seconds: 60);

/// …at most this many times.
const renewRetries = 2;

/// The deleted account's answer, given without a request.
const accountDeletedAnswer = ApiFailure(403, 'account_deleted');

/// Answered without a request when a renewal or a sign-in brought another
/// player's tokens: a request made for the old player is never sent with
/// the new one's (R7). The caller's next try is the new player's.
const accountChangedAnswer = ApiFailure(409, 'account_changed');

/// What signing in gave.
sealed class SignInOutcome {
  const SignInOutcome();
}

final class SignedIn extends SignInOutcome {
  const SignedIn(this.session, {this.created});

  final Session session;

  /// The creation answer's `created`: false for a returning player.
  final bool? created;
}

/// The answer that stopped it, for the caller.
final class SignInFailed extends SignInOutcome {
  const SignInFailed(this.result);

  final ApiResult result;
}

/// What [TokenAuthorizedApi] needs from the account (contracts/account.md).
abstract interface class SessionAuthority {
  /// `403 account_deleted` was seen, on this launch or an earlier one.
  bool get isDeleted;

  /// Signs in with the install id, one sign-in at a time.
  Future<SignInOutcome> signIn();

  /// A token answer, already stored: the account checks its player (R7).
  Future<void> tokensStored(TokenPair pair);

  /// `403 account_deleted`.
  Future<void> accountDeleted();
}

/// A session from a token answer: the expiry on trusted time (R2).
Session sessionOf(TokenPair pair, int nowMs) => Session(
  playerId: pair.playerId,
  access: pair.access,
  refresh: pair.refresh,
  accessExpiresAtMs: nowMs + pair.accessExpiresIn * 1000,
);

final class TokenAuthorizedApi implements AuthorizedApi {
  TokenAuthorizedApi({
    required this._api,
    required this._sessions,
    required this._authority,
    required this._nowMs,
    required this._elapsedMs,
  });

  final ApiClient _api;
  final SessionStore _sessions;
  final SessionAuthority _authority;

  /// Trusted time, for the expiry.
  final int Function() _nowMs;

  /// The uptime counter, for the renewal's retry window.
  final int Function() _elapsedMs;

  Session? _session;
  bool _loaded = false;
  Future<_Renewal>? _renewing;

  /// The stored session, read once.
  Future<Session?> currentSession() async {
    if (!_loaded) {
      _session = await _sessions.read();
      _loaded = true;
    }
    return _session;
  }

  /// Writes [pair] as the session, in one write, before anything uses it,
  /// then tells the account (R2, R7).
  Future<Session> storeTokens(TokenPair pair) async {
    final session = sessionOf(pair, _nowMs());
    try {
      await _sessions.write(session);
    } on PlatformException {
      // Kept in memory for this run, so a rotated refresh token isn't lost.
      // The next launch finds the older session, whose renewal fails, and
      // signs in again with the install id.
    }
    _session = session;
    _loaded = true;
    await _authority.tokensStored(pair);
    return session;
  }

  /// Forgets the session: a fresh database's first open (R2).
  Future<void> clearSession() async {
    await _sessions.clear();
    _session = null;
    _loaded = true;
  }

  @override
  Future<ApiResult> send(ApiRequest request) async {
    if (_authority.isDeleted) return accountDeletedAnswer;
    var session = await currentSession();
    if (session == null) {
      switch (await _authority.signIn()) {
        case SignedIn(session: final signedIn):
          session = signedIn;
        case SignInFailed(:final result):
          return result;
      }
    }
    if (request.forPlayer case final player? when player != session.playerId) {
      return accountChangedAnswer;
    }
    if (session.accessExpiresAtMs - _nowMs() < renewMargin.inMilliseconds) {
      switch (await _renew(session)) {
        case _Renewed(session: final renewed)
            when renewed.playerId != session.playerId:
          return accountChangedAnswer;
        case _Renewed(session: final renewed):
          session = renewed;
        case _RenewalFailed(:final result):
          return result;
      }
    }
    final result = await _api.send(request.withBearer(session.access));
    return switch (result) {
      ApiFailure(status: 401, code: 'token_expired') => _afterExpired(
        request,
        session,
      ),
      ApiFailure(status: 401, code: 'token_invalid') => _afterInvalid(
        request,
        session,
      ),
      ApiFailure(status: 403, code: 'account_deleted') => _deleted(result),
      _ => result,
    };
  }

  /// `token_expired`: renew, then repeat once.
  Future<ApiResult> _afterExpired(ApiRequest request, Session stale) async =>
      switch (await _renew(stale)) {
        _Renewed(:final session) => _repeat(request, stale, session),
        _RenewalFailed(:final result) => result,
      };

  /// `token_invalid`: renew once and repeat once; a second `token_invalid`
  /// signs in again, then repeats once more.
  Future<ApiResult> _afterInvalid(ApiRequest request, Session stale) async {
    final Session renewed;
    switch (await _renew(stale)) {
      case _Renewed(:final session):
        renewed = session;
      case _RenewalFailed(:final result):
        return result;
    }
    final repeat = await _repeat(request, stale, renewed);
    if (repeat case ApiFailure(status: 401, code: 'token_invalid')) {
      return switch (await _authority.signIn()) {
        SignedIn(:final session) => _repeat(request, stale, session),
        SignInFailed(:final result) => result,
      };
    }
    return repeat;
  }

  /// [request] again with [session], unless [session] is another player's
  /// than [stale].
  Future<ApiResult> _repeat(
    ApiRequest request,
    Session stale,
    Session session,
  ) async => session.playerId == stale.playerId
      ? _sendOnce(request, session)
      : accountChangedAnswer;

  /// One send with [session], no more token handling than `account_deleted`.
  Future<ApiResult> _sendOnce(ApiRequest request, Session session) async {
    final result = await _api.send(request.withBearer(session.access));
    if (result case ApiFailure(status: 403, code: 'account_deleted')) {
      return _deleted(result);
    }
    return result;
  }

  Future<ApiResult> _deleted(ApiFailure result) async {
    await _authority.accountDeleted();
    return result;
  }

  /// Renews [stale], unless another caller already replaced it. Concurrent
  /// callers share one renewal.
  Future<_Renewal> _renew(Session stale) async {
    final current = _session;
    if (current != null && !identical(current, stale)) {
      return _Renewed(current);
    }
    return _renewing ??= _renewNow(stale).whenComplete(() => _renewing = null);
  }

  Future<_Renewal> _renewNow(Session stale) async {
    final firstAt = _elapsedMs();
    for (var attempt = 0; ; attempt++) {
      final result = await _api.send(
        ApiRequest.post(
          ApiPaths.refresh,
          receiveTimeout: authReceiveTimeout,
          body: {'refresh': stale.refresh},
        ),
      );
      switch (result) {
        case ApiOk(:final json):
          // Tokens stored meanwhile (a sign-in, a link's switch) are newer
          // than this answer: keep them, and the caller sees whose they are.
          if (_session case final current? when !identical(current, stale)) {
            return _Renewed(current);
          }
          try {
            return _Renewed(await storeTokens(TokenPair.fromJson(json)));
          } on WireFormatException {
            return const _RenewalFailed(ApiFailure(200, 'server_error'));
          }
        case ApiFailure(status: 401, code: 'token_expired' || 'token_invalid'):
          return _signInInstead();
        case ApiFailure(status: 403, code: 'account_deleted'):
          return _RenewalFailed(await _deleted(result));
        case ApiFailure():
          return _RenewalFailed(result);
        case ApiUnreachable():
          final inWindow =
              _elapsedMs() - firstAt < renewRetryWindow.inMilliseconds;
          if (attempt >= renewRetries || !inWindow) {
            return _signInInstead();
          }
      }
    }
  }

  Future<_Renewal> _signInInstead() async =>
      switch (await _authority.signIn()) {
        SignedIn(:final session) => _Renewed(session),
        SignInFailed(:final result) => _RenewalFailed(result),
      };
}

sealed class _Renewal {
  const _Renewal();
}

final class _Renewed extends _Renewal {
  const _Renewed(this.session);

  final Session session;
}

final class _RenewalFailed extends _Renewal {
  const _RenewalFailed(this.result);

  final ApiResult result;
}
