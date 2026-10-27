// The install id (specs/011-m06-identity-sync, contracts/account.md
// "Stores", research R1): created once, kept where a re-install on the same
// phone doesn't erase it, and sent only to account creation.
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_android/shared_preferences_android.dart';
import 'package:uuid/data.dart';
import 'package:uuid/rng.dart';
import 'package:uuid/uuid.dart';
import 'package:wassal/core/account/domain/account.dart';

abstract interface class InstallIdStore {
  /// The stored id, or a new one written to every store the platform has.
  /// Never null.
  Future<InstallId> readOrCreate();
}

/// A new install id: version 4 from a cryptographic generator, passed
/// explicitly rather than left to the package's default (research R1).
InstallId newInstallId() => InstallId.parse(
  const Uuid().v4(config: const V4Options(null, CryptoRNG())),
);

/// The keychain's options for the install id and the session (research R1,
/// R2): readable after the first unlock, on this device only, never in
/// iCloud.
const keychainOptions = IOSOptions(
  accessibility: KeychainAccessibility.first_unlock_this_device,
  synchronizable: false,
);

/// Android: Block Store through `wassal/install_id`, then the backed-up
/// preference file `wassal_install.xml`. Whichever lacks the id gets it,
/// unless it couldn't be read: it may hold an id a new one would replace.
/// Neither store failing ever fails the app.
final class AndroidInstallIdStore implements InstallIdStore {
  AndroidInstallIdStore({
    this._channel = const MethodChannel('wassal/install_id'),
    SharedPreferencesAsync? preferences,
  }) : _preferences =
           preferences ?? SharedPreferencesAsync(options: preferenceOptions);

  /// The preference file Android's own backup carries (research R1).
  static const preferenceOptions = SharedPreferencesAsyncAndroidOptions(
    backend: SharedPreferencesAndroidBackendLibrary.SharedPreferences,
    originalSharedPreferencesOptions: AndroidSharedPreferencesStoreOptions(
      fileName: 'wassal_install',
    ),
  );

  /// The id's key in `wassal_install.xml`.
  static const preferenceKey = 'install_id';

  final MethodChannel _channel;
  final SharedPreferencesAsync _preferences;

  @override
  Future<InstallId> readOrCreate() async {
    final blockStore = await _readBlockStore();
    final file = await _readFile();
    final fromBlockStore = InstallId.tryParse(blockStore.value);
    final fromFile = InstallId.tryParse(file.value);
    final id = fromBlockStore ?? fromFile ?? newInstallId();
    if (blockStore.read && fromBlockStore != id) await _writeBlockStore(id);
    if (file.read && fromFile != id) await _writeFile(id);
    return id;
  }

  /// The stored text, and whether the store could be read at all.
  Future<({String? value, bool read})> _readBlockStore() async {
    try {
      return (value: await _channel.invokeMethod<String>('read'), read: true);
    } on PlatformException {
      return (value: null, read: false);
    } on MissingPluginException {
      return (value: null, read: false);
    }
  }

  Future<void> _writeBlockStore(InstallId id) async {
    try {
      await _channel.invokeMethod<bool>('write', {'id': id.value});
    } on PlatformException {
      return;
    } on MissingPluginException {
      return;
    }
  }

  Future<({String? value, bool read})> _readFile() async {
    try {
      return (value: await _preferences.getString(preferenceKey), read: true);
    } on PlatformException {
      return (value: null, read: false);
    }
  }

  Future<void> _writeFile(InstallId id) async {
    try {
      await _preferences.setString(preferenceKey, id.value);
    } on PlatformException {
      return;
    }
  }
}

/// iOS: the keychain, whose items outlive the app's deletion (research R1).
final class KeychainInstallIdStore implements InstallIdStore {
  KeychainInstallIdStore({this._storage = storage});

  static const keychainKey = 'wassal.install_id';

  static const storage = FlutterSecureStorage(iOptions: keychainOptions);

  final FlutterSecureStorage _storage;

  @override
  Future<InstallId> readOrCreate() async {
    final String? stored;
    try {
      stored = await _storage.read(key: keychainKey);
    } on PlatformException {
      // The keychain may hold the id: one for this run, written nowhere.
      return newInstallId();
    }
    return InstallId.tryParse(stored) ?? _create();
  }

  Future<InstallId> _create() async {
    final id = newInstallId();
    try {
      await _storage.write(key: keychainKey, value: id.value);
    } on PlatformException {
      // Kept for this run; the next launch tries again.
    }
    return id;
  }
}

/// [InstallIdStore] in memory: tests, and platforms with no store.
final class MemoryInstallIdStore implements InstallIdStore {
  MemoryInstallIdStore([this.id]);

  InstallId? id;

  @override
  Future<InstallId> readOrCreate() async => id ??= newInstallId();
}
