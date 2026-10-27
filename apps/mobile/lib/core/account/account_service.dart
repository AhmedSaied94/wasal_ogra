// The player's account on this phone (specs/011-m06-identity-sync,
// contracts/account.md, research R5–R7): the first open, signing in with the
// install id, account changes and deletion. Screens read its providers; the
// sync and the bootstrap call it.
import 'dart:async';
import 'dart:math';

import 'package:wassal/core/account/authorized_api.dart';
import 'package:wassal/core/account/domain/account.dart';
import 'package:wassal/core/account/domain/link_outcome.dart';
import 'package:wassal/core/account/drift_account_store.dart';
import 'package:wassal/core/account/install_id_store.dart';
import 'package:wassal/core/account/session_store.dart';
import 'package:wassal/core/network/api_client.dart';
import 'package:wassal/core/platform/connectivity.dart';
import 'package:wassal/core/sync/domain/wire/link.dart';
import 'package:wassal/core/sync/domain/wire/reader.dart';
import 'package:wassal/core/sync/domain/wire/state.dart';
import 'package:wassal/core/sync/domain/wire/token_pair.dart';
import 'package:wassal/core/sync/sync_engine.dart';

/// How long boot waits for the first open's outcome after startup
/// completes (research R6): a UX bound, not a balancing number.
const firstOpenWait = Duration(seconds: 3);

/// The locale account creation sends (B02).
const accountLocale = 'ar-EG';

abstract interface class AccountService {
  /// Synchronous after startup.
  AccountStatus get status;
  Stream<AccountStatus> get statuses;
  Profile? get profile;

  /// The first open's work (R6): install id, account creation, a returning
  /// player's state. Runs once per install; later launches answer
  /// `notFirstOpen` at once.
  Future<FirstOpenOutcome> firstOpen();

  /// Boot calls it just before it leaves the Loading screen. Past it,
  /// firstOpen() leaves a returning player's state to the sync engine (R6).
  void handOver();

  /// Makes sure there is an active session, signing in with the install id
  /// when there is none. The sync and the bootstrap call it; screens don't.
  Future<bool> ensureSession();

  /// R8. Flushes pending operations (up to 15 s), then links.
  Future<LinkOutcome> link(
    String googleIdToken, {
    LinkResolve? resolve,
    String? existingPlayerId,
  });
}

final class ServerAccountService
    implements AccountService, SessionAuthority, SyncAccount {
  ServerAccountService({
    required this._api,
    required this._installIds,
    required SessionStore sessions,
    required this._store,
    required this._connectivity,
    required int Function() nowMs,
    required this._elapsedMs,
    required this._platform,
    this._states,
  }) : _nowMs = nowMs {
    authorized = TokenAuthorizedApi(
      api: _api,
      sessions: sessions,
      authority: this,
      nowMs: nowMs,
      elapsedMs: _elapsedMs,
    );
  }

  final ApiClient _api;
  final InstallIdStore _installIds;
  final DriftAccountStore _store;
  final ConnectivitySource _connectivity;
  final int Function() _nowMs;

  /// The uptime counter, for the creation's `429` wait.
  final int Function() _elapsedMs;

  /// `android` or `ios`, as account creation sends it.
  final String _platform;

  /// Takes a returning player's state on the first open (R6, R12).
  final StateApplier? _states;

  /// Every player call goes through it.
  late final TokenAuthorizedApi authorized;

  final _changes = StreamController<void>.broadcast();
  final _restorations = StreamController<void>.broadcast();
  SyncEngine? _sync;
  StreamSubscription<SyncEvent>? _syncEvents;

  /// A returning player's state is still to take, by the sync (R6). In
  /// memory: after a kill, the stale or ahead path takes it.
  bool _restoreWanted = false;
  Future<FirstOpenOutcome>? _firstOpen;
  Future<SignInOutcome>? _signingIn;
  bool _handedOver = false;

  /// No creation before this uptime reading: a creation `429`'s
  /// `retry_after_s` (FR-004).
  int? _signInAfterElapsedMs;

  /// Whether boot has left the Loading screen.
  bool get handedOver => _handedOver;

  @override
  int? get signInAfterElapsedMs => _signInAfterElapsedMs;

  /// A value after every change of the account row.
  Stream<void> get changes => _changes.stream;

  /// A value when a returning player's state, found past the hand-over,
  /// was taken by the sync (`progressRestoredProvider`, for M07).
  Stream<void> get restorations => _restorations.stream;

  /// The sync, once it runs: a restore found past the hand-over goes to it.
  void attachSync(SyncEngine sync) {
    _sync = sync;
    unawaited(_syncEvents?.cancel());
    _syncEvents = sync.events.listen((event) {
      if (event case StateTaken(why: StateWhy.firstOpen)) {
        unawaited(_restoredBySync());
      }
    });
    if (_restoreWanted) sync.requestRestore();
  }

  @override
  AccountStatus get status => _store.account.status;

  @override
  Stream<AccountStatus> get statuses =>
      _changes.stream.map((_) => status).distinct();

  @override
  Profile? get profile => _store.account.profile;

  @override
  bool get isDeleted => status == AccountStatus.deleted;

  @override
  String? get playerId => _store.account.playerId;

  /// What the server last said of the player: a state or a bootstrap
  /// (FR-009). Null keeps the stored value.
  Future<void> updateProfile({
    String? displayName,
    int? driverLevel,
    List<String>? providers,
  }) async {
    await _store.setProfile(
      displayName: displayName,
      driverLevel: driverLevel,
      providers: providers,
    );
    _changed();
  }

  @override
  Future<FirstOpenOutcome> firstOpen() => _firstOpen ??= _runFirstOpen();

  @override
  void handOver() => _handedOver = true;

  @override
  Future<bool> ensureSession() async {
    if (isDeleted) return false;
    if (await authorized.currentSession() != null) return true;
    return await signIn() is SignedIn;
  }

  @override
  Future<SignInOutcome> signIn() {
    if (isDeleted) {
      return Future.value(const SignInFailed(accountDeletedAnswer));
    }
    final after = _signInAfterElapsedMs;
    if (after != null && _elapsedMs() < after) {
      return Future.value(
        SignInFailed(
          ApiFailure(
            429,
            'rate_limited',
            retryAfter: Duration(milliseconds: after - _elapsedMs()),
          ),
        ),
      );
    }
    return _signingIn ??= _signInNow().whenComplete(() => _signingIn = null);
  }

  @override
  Future<void> tokensStored(TokenPair pair) async {
    // A first answer, the same player, or another (R7): the account follows
    // the answer, and the sync blocks on a player its base doesn't hold.
    await _store.signedIn(playerId: pair.playerId, providers: pair.providers);
    _changed();
  }

  @override
  Future<void> accountDeleted() async {
    if (isDeleted) return;
    await _store.markDeleted();
    _changed();
  }

  @override
  Future<LinkOutcome> link(
    String googleIdToken, {
    LinkResolve? resolve,
    String? existingPlayerId,
  }) async {
    // A conflict's summaries are the server's: what is pending goes first,
    // so they include it.
    final flushed = await _sync?.flush() ?? true;
    final result = await authorized.send(
      ApiRequest.post(
        ApiPaths.link,
        receiveTimeout: authReceiveTimeout,
        body: {
          'provider': 'google',
          'id_token': googleIdToken,
          'resolve': ?resolve?.wire,
          'existing_player_id': ?existingPlayerId,
        },
      ),
    );
    try {
      return await _linked(result, flushed: flushed);
    } on WireFormatException {
      return LinkFailed('server_error', flushed: flushed);
    }
  }

  Future<LinkOutcome> _linked(ApiResult result, {required bool flushed}) async {
    switch (result) {
      case ApiOk(:final json) when json.containsKey('access'):
        // switch_to_existing: that player's tokens. The sync takes its state
        // before anything is sent with them (R7).
        final pair = TokenPair.fromJson(json);
        await authorized.storeTokens(pair);
        _sync?.request(SyncTrigger.accountActive);
        return Linked(pair.providers.toSet(), flushed: flushed);
      case ApiOk(:final json):
        final linked = LinkResult.fromJson(json);
        await updateProfile(providers: linked.providers);
        return Linked(linked.providers.toSet(), flushed: flushed);
      case ApiFailure(status: 409, code: 'provider_in_use', :final details):
        final (:current, :existing) = conflictOf(details);
        return Conflict(current, existing, flushed: flushed);
      case ApiFailure(status: 409, code: 'provider_already_linked'):
        return ProviderAlreadyLinked(flushed: flushed);
      case ApiFailure(
        status: 422,
        code: 'provider_token_invalid',
        :final details,
      ):
        return GoogleTokenRefused(switch (details['reason']) {
          final String reason => reason,
          _ => 'malformed',
        }, flushed: flushed);
      case ApiUnreachable():
        return LinkUnreachable(flushed: flushed);
      case ApiFailure(:final code):
        return LinkFailed(code, flushed: flushed);
    }
  }

  void dispose() {
    unawaited(_syncEvents?.cancel());
    unawaited(_changes.close());
    unawaited(_restorations.close());
  }

  Future<FirstOpenOutcome> _runFirstOpen() async {
    if (status != AccountStatus.none) return FirstOpenOutcome.notFirstOpen;
    // A previous install's tokens can outlive it in the keychain, and
    // belong to a state this database never took (R2).
    await authorized.clearSession();
    await _store.markFirstOpen(_nowMs());
    await _installIds.readOrCreate();
    if (!await _connectivity.isOnline()) return FirstOpenOutcome.offline;
    return switch (await signIn()) {
      SignedIn(created: false) => _restore(),
      SignedIn() => FirstOpenOutcome.newPlayer,
      SignInFailed() => FirstOpenOutcome.offline,
    };
  }

  /// A returning player (R6): its state, taken here only before the
  /// hand-over, so never while a trip may be on screen. Past it, or when the
  /// state can't be fetched, the sync takes it.
  Future<FirstOpenOutcome> _restore() async {
    final states = _states;
    final player = playerId;
    if (_handedOver || states == null || player == null) {
      return _restoreLater(FirstOpenOutcome.timedOut);
    }
    final result = await authorized.send(
      ApiRequest.get(
        ApiPaths.state,
        receiveTimeout: readReceiveTimeout,
        forPlayer: player,
      ),
    );
    if (result is! ApiOk) return _restoreLater(FirstOpenOutcome.offline);
    final StateSnapshot snapshot;
    try {
      snapshot = StateSnapshot.fromJson(result.json);
    } on WireFormatException {
      return _restoreLater(FirstOpenOutcome.offline);
    }
    if (_handedOver) return _restoreLater(FirstOpenOutcome.timedOut);
    await states.apply(
      snapshot,
      StateWhy.firstOpen,
      playerId: player,
      sentAtElapsedMs: result.sentAtElapsedMs,
      receivedAtElapsedMs: result.receivedAtElapsedMs,
    );
    await _store.markRestored(_nowMs());
    _changed();
    return FirstOpenOutcome.restored;
  }

  FirstOpenOutcome _restoreLater(FirstOpenOutcome outcome) {
    _restoreWanted = true;
    _sync?.requestRestore();
    return outcome;
  }

  Future<void> _restoredBySync() async {
    _restoreWanted = false;
    await _store.markRestored(_nowMs());
    _changed();
    if (!_restorations.isClosed) _restorations.add(null);
  }

  Future<SignInOutcome> _signInNow() async {
    final id = await _installIds.readOrCreate();
    final result = await _api.send(
      ApiRequest.post(
        ApiPaths.anonymous,
        receiveTimeout: authReceiveTimeout,
        body: {
          'install_id': id.value,
          'platform': _platform,
          'locale': accountLocale,
        },
      ),
    );
    switch (result) {
      case ApiOk(:final json):
        final TokenPair pair;
        try {
          pair = TokenPair.fromJson(json);
        } on WireFormatException {
          return SignInFailed(ApiFailure(result.status, 'server_error'));
        }
        final session = await authorized.storeTokens(pair);
        return SignedIn(session, created: pair.created);
      case ApiFailure(status: 429):
        _signInAfterElapsedMs = _elapsedMs() + _waitOf(result).inMilliseconds;
        return SignInFailed(result);
      case ApiFailure(status: 403, code: 'account_deleted'):
        await accountDeleted();
        return SignInFailed(result);
      case ApiFailure() || ApiUnreachable():
        return SignInFailed(result);
    }
  }

  void _changed() {
    if (!_changes.isClosed) _changes.add(null);
  }
}

/// A creation `429`'s wait: `details.retry_after_s` or `Retry-After`,
/// whichever is longer.
Duration _waitOf(ApiFailure failure) {
  final seconds = switch (failure.details['retry_after_s']) {
    final int s when s > 0 => s,
    _ => 0,
  };
  return Duration(seconds: max(seconds, failure.retryAfter?.inSeconds ?? 0));
}
