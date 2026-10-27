// The bootstrap (specs/011-m06-identity-sync, research R15): trusted time
// on the server's, the cached blocks the app reads offline, the profile, a
// forced content check when the server has a newer pack, and the
// `state_version` the sync's step 4 compares with its base. The wallet in
// it is never applied: the full state or the next batch carries it, with
// its operations.
import 'dart:async';

import 'package:wassal/core/account/authorized_api.dart';
import 'package:wassal/core/account/domain/account_record.dart';
import 'package:wassal/core/account/drift_account_store.dart';
import 'package:wassal/core/economy/economy_sync.dart';
import 'package:wassal/core/network/api_client.dart';
import 'package:wassal/core/sync/domain/wire/bootstrap.dart';
import 'package:wassal/core/sync/domain/wire/reader.dart';

/// At least this long between two bootstraps, unless one is forced.
const bootstrapSpacing = Duration(seconds: 60);

/// Where the `client` block goes: US4's update state (research R18).
abstract interface class ClientBlockSink {
  void client(ClientBlock block);
}

final class NoClientBlock implements ClientBlockSink {
  const NoClientBlock();

  @override
  void client(ClientBlock block) {}
}

/// Writes what the server says of the player to the account.
typedef BootstrapProfileWriter = Future<void> Function({
  String? displayName,
  int? driverLevel,
  List<String>? providers,
});

final class BootstrapService {
  BootstrapService({
    required this._api,
    required this._store,
    required this._economy,
    required this._writeProfile,
    required this._checkContent,
    required this._activeContentVersion,
    required this._nowMs,
    required this._elapsedMs,
    this._clients = const NoClientBlock(),
  });

  final AuthorizedApi _api;
  final DriftAccountStore _store;
  final EconomySync _economy;
  final BootstrapProfileWriter _writeProfile;

  /// `ContentUpdater.check(force: true)`.
  final Future<void> Function() _checkContent;
  final int Function() _activeContentVersion;

  /// Trusted time, for `received_at_ms`.
  final int Function() _nowMs;

  /// The uptime counter, for the spacing.
  final int Function() _elapsedMs;
  final ClientBlockSink _clients;

  final _infos = StreamController<ServerInfo>.broadcast();
  Future<bool>? _running;
  int? _lastSuccessElapsedMs;

  /// The cached row: what the providers read, offline too (FR-015).
  ServerInfo get info => _store.serverInfo;

  /// A value after every bootstrap written.
  Stream<ServerInfo> get infos => _infos.stream;

  /// The last bootstrap's `state_version`, or null before any: the sync's
  /// step 4 takes the full state when it is above the base's.
  int? get stateVersion => _store.serverInfo.stateVersion;

  /// Runs a bootstrap unless one succeeded within [bootstrapSpacing], or
  /// [force]. One at a time. True when one ran and its answer was taken.
  Future<bool> refresh({bool force = false}) {
    if (_running case final running?) return running;
    final last = _lastSuccessElapsedMs;
    if (!force &&
        last != null &&
        _elapsedMs() - last < bootstrapSpacing.inMilliseconds) {
      return Future.value(false);
    }
    return _running = _refresh().whenComplete(() => _running = null);
  }

  Future<bool> _refresh() async {
    final result = await _api.send(
      const ApiRequest.get(
        ApiPaths.bootstrap,
        receiveTimeout: readReceiveTimeout,
      ),
    );
    if (result is! ApiOk) return false;
    final BootstrapSnapshot snapshot;
    try {
      snapshot = BootstrapSnapshot.fromJson(result.json);
    } on WireFormatException {
      return false;
    }
    final roundTripMs = result.receivedAtElapsedMs - result.sentAtElapsedMs;
    await _economy.anchorOnServer(
      snapshot.serverTimeMs + roundTripMs ~/ 2,
      elapsedAtResponseMs: result.receivedAtElapsedMs,
    );
    await _store.saveBootstrap(
      receivedAtMs: _nowMs(),
      serverTimeMs: snapshot.serverTimeMs,
      stateVersion: snapshot.stateVersion,
      contentVersion: snapshot.contentVersion,
      client: snapshot.raw['client'],
      entitlements: snapshot.raw['entitlements'],
      daily: snapshot.raw['daily'],
      comebackClaimable: snapshot.comebackClaimable,
    );
    _lastSuccessElapsedMs = _elapsedMs();
    if (!_infos.isClosed) _infos.add(_store.serverInfo);
    final player = snapshot.player;
    await _writeProfile(
      displayName: player.displayName,
      driverLevel: player.driverLevel,
      providers: player.providers,
    );
    _clients.client(snapshot.client);
    if (snapshot.contentVersion case final version?
        when version > _activeContentVersion()) {
      // The pack downloads in the background; its own errors stay its own.
      unawaited(_checkContent().catchError((Object _) {}));
    }
    return true;
  }

  void dispose() => unawaited(_infos.close());
}
