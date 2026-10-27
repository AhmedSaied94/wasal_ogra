import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_android/shared_preferences_android.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';
import 'package:wassal/core/account/domain/account.dart';
import 'package:wassal/core/account/install_id_store.dart';

// The install id's stores (specs/011-m06-identity-sync, contracts/
// account.md "Stores", research R1): Block Store, then the preference file,
// then a new id, written to whichever store lacks it.

const _channel = MethodChannel('wassal/install_id');
const _id = '3f2b8c1e-9a4d-4e7f-8b21-5c6d7e8f9a0b';
const _other = '7d1e2f3a-4b5c-4d6e-9f70-8a9b0c1d2e3f';

/// The preference file, recording the options each call names.
base class _File extends InMemorySharedPreferencesAsync {
  _File([super.data = const {}]) : super.withData();

  final options = <SharedPreferencesOptions>[];

  /// Reads throw, as a file that can't be read does.
  bool getFails = false;

  @override
  Future<String?> getString(String key, SharedPreferencesOptions options) {
    this.options.add(options);
    if (getFails) throw PlatformException(code: 'io');
    return super.getString(key, options);
  }

  @override
  Future<bool> setString(
    String key,
    String value,
    SharedPreferencesOptions options,
  ) {
    this.options.add(options);
    return super.setString(key, value, options);
  }
}

/// Block Store behind the channel: [stored], and every call.
final class _BlockStore {
  _BlockStore({this.stored});

  String? stored;
  PlatformException? failure;

  /// Reads answer the channel's error, as Play services failing does.
  bool readFails = false;
  final calls = <MethodCall>[];

  Future<Object?> handle(MethodCall call) async {
    calls.add(call);
    if (failure case final error?) throw error;
    if (readFails && call.method == 'read') {
      throw PlatformException(code: 'read_failed');
    }
    switch (call.method) {
      case 'read':
        return stored;
      case 'write':
        stored = (call.arguments as Map<Object?, Object?>)['id']! as String;
        return true;
    }
    return null;
  }
}

/// A keychain that can't be read, as before the first unlock.
final class _UnreadableKeychain extends FlutterSecureStorage {
  const _UnreadableKeychain();

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) => throw PlatformException(code: 'locked');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _File file;
  late _BlockStore blockStore;

  void install({String? inBlockStore, String? inFile, bool channel = true}) {
    file = _File({AndroidInstallIdStore.preferenceKey: ?inFile});
    SharedPreferencesAsyncPlatform.instance = file;
    blockStore = _BlockStore(stored: inBlockStore);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, channel ? blockStore.handle : null);
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, null),
    );
  }

  Future<String?> fileValue() =>
      file.getString(AndroidInstallIdStore.preferenceKey, file.options.last);

  group('Android', () {
    test('Block Store first, and the file gets what it lacks', () async {
      install(inBlockStore: _id);
      final id = await AndroidInstallIdStore().readOrCreate();
      expect(id.value, _id);
      expect(await fileValue(), _id);
      expect(blockStore.calls.map((c) => c.method), ['read']);
    });

    test('the file second, and Block Store gets what it lacks', () async {
      install(inFile: _id);
      final id = await AndroidInstallIdStore().readOrCreate();
      expect(id.value, _id);
      expect(blockStore.stored, _id);
      expect(blockStore.calls.last.arguments, {'id': _id});
    });

    test('Block Store wins when the two disagree', () async {
      install(inBlockStore: _id, inFile: _other);
      expect((await AndroidInstallIdStore().readOrCreate()).value, _id);
      expect(await fileValue(), _id);
    });

    test('a new id when neither has one, written to both', () async {
      install();
      final id = await AndroidInstallIdStore().readOrCreate();
      expect(blockStore.stored, id.value);
      expect(await fileValue(), id.value);
    });

    test('a channel error or null falls back to the file', () async {
      install(inFile: _id);
      blockStore.failure = PlatformException(code: 'blockstore');
      expect((await AndroidInstallIdStore().readOrCreate()).value, _id);

      install(inFile: _id, channel: false);
      expect((await AndroidInstallIdStore().readOrCreate()).value, _id);
    });

    test('a Block Store that fails to read is never written over', () async {
      install(inBlockStore: _id);
      blockStore.readFails = true;

      final id = await AndroidInstallIdStore().readOrCreate();

      expect(id.value, isNot(_id));
      expect(blockStore.stored, _id);
      expect(blockStore.calls.map((c) => c.method), ['read']);
      expect(await fileValue(), id.value);

      // Read again, its id wins, and the file follows it.
      blockStore.readFails = false;
      expect((await AndroidInstallIdStore().readOrCreate()).value, _id);
      expect(await fileValue(), _id);
    });

    test('a file that fails to read is never written over', () async {
      install(inBlockStore: _id, inFile: _other);
      file.getFails = true;

      expect((await AndroidInstallIdStore().readOrCreate()).value, _id);

      file.getFails = false;
      expect(await fileValue(), _other);
    });

    test('a value that is not an id is ignored', () async {
      install(inBlockStore: 'not-an-id', inFile: _id.toUpperCase());
      final id = await AndroidInstallIdStore().readOrCreate();
      expect(id.value, isNot(_id));
      expect(blockStore.stored, id.value);
      expect(await fileValue(), id.value);
    });

    test('two calls on a fresh install return the same id', () async {
      install();
      final store = AndroidInstallIdStore();
      final first = await store.readOrCreate();
      expect(await store.readOrCreate(), first);
      expect(await AndroidInstallIdStore().readOrCreate(), first);
    });

    test(
      'the file is wassal_install.xml on the SharedPreferences backend',
      () async {
        install();
        await AndroidInstallIdStore().readOrCreate();
        expect(file.options, isNotEmpty);
        for (final options in file.options) {
          final android = options as SharedPreferencesAsyncAndroidOptions;
          expect(
            android.backend,
            SharedPreferencesAndroidBackendLibrary.SharedPreferences,
          );
          expect(
            android.originalSharedPreferencesOptions?.fileName,
            'wassal_install',
          );
        }
      },
    );
  });

  group('new ids', () {
    test('are lowercase version 4', () {
      for (var i = 0; i < 200; i++) {
        final id = newInstallId().value;
        expect(InstallId.tryParse(id), isNotNull);
        expect(id, id.toLowerCase());
        expect(id[14], '4');
      }
    });

    test('differ', () {
      expect({for (var i = 0; i < 1000; i++) newInstallId()}, hasLength(1000));
    });
  });

  group('iOS', () {
    late Map<String, String> keychain;

    setUp(() {
      keychain = {};
      FlutterSecureStorage.setMockInitialValues(keychain);
    });

    test('reads the keychain, or writes a new id to it', () async {
      final first = await KeychainInstallIdStore().readOrCreate();
      expect(keychain, {KeychainInstallIdStore.keychainKey: first.value});
      expect(await KeychainInstallIdStore().readOrCreate(), first);

      keychain[KeychainInstallIdStore.keychainKey] = _id;
      expect((await KeychainInstallIdStore().readOrCreate()).value, _id);
    });

    test('a keychain that fails to read is never written over', () async {
      final id = await KeychainInstallIdStore(
        storage: const _UnreadableKeychain(),
      ).readOrCreate();

      expect(InstallId.tryParse(id.value), isNotNull);
      expect(keychain, isEmpty);
    });

    test('the key is wassal.install_id, on this device only', () {
      expect(KeychainInstallIdStore.keychainKey, 'wassal.install_id');
      final options = KeychainInstallIdStore.storage.iOptions.toMap();
      expect(options['accessibility'], 'first_unlock_this_device');
      expect(options['synchronizable'], 'false');
    });
  });

  test('the memory store keeps its id', () async {
    final store = MemoryInstallIdStore();
    expect(await store.readOrCreate(), await store.readOrCreate());
  });
}
