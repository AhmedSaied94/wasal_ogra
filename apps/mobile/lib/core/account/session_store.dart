// The session's tokens (specs/011-m06-identity-sync, contracts/account.md
// "Stores", research R2): one secure-storage value, so the access and
// refresh tokens are always written together.
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:wassal/core/account/domain/account.dart';
import 'package:wassal/core/account/install_id_store.dart' show keychainOptions;

abstract interface class SessionStore {
  /// The stored session, or null when there is none or it can't be read.
  Future<Session?> read();

  /// One call: the access and refresh tokens together.
  Future<void> write(Session session);

  Future<void> clear();
}

/// [SessionStore] over `flutter_secure_storage`, key `wassal.session`.
final class SecureSessionStore implements SessionStore {
  SecureSessionStore({this._storage = storage});

  static const storageKey = 'wassal.session';

  static const storage = FlutterSecureStorage(
    iOptions: keychainOptions,
    aOptions: androidOptions,
  );

  /// No `storageNamespace`, so the plugin writes the four files the backup
  /// rules exclude by name (research R2); a plugin upgrade must re-check
  /// them. `resetOnError` stays on: a store that can't be read is wiped, and
  /// the app signs in again with its install id.
  static const androidOptions = AndroidOptions(resetOnError: true);

  final FlutterSecureStorage _storage;

  @override
  Future<Session?> read() async {
    try {
      return Session.tryDecode(await _storage.read(key: storageKey));
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<void> write(Session session) =>
      _storage.write(key: storageKey, value: session.encode());

  @override
  Future<void> clear() async {
    try {
      await _storage.delete(key: storageKey);
    } on PlatformException {
      return;
    }
  }
}

/// [SessionStore] in memory, for tests.
final class MemorySessionStore implements SessionStore {
  MemorySessionStore([this.session]);

  Session? session;

  /// How many writes there were.
  int writes = 0;

  /// Writes throw, as a keystore that fails does.
  bool failWrites = false;

  @override
  Future<Session?> read() async => session;

  @override
  Future<void> write(Session session) async {
    if (failWrites) throw PlatformException(code: 'write_failed');
    writes++;
    this.session = session;
  }

  @override
  Future<void> clear() async => session = null;
}
