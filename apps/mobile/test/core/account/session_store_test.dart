import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/account/domain/account.dart';
import 'package:wassal/core/account/session_store.dart';

// The session's secure storage (specs/011-m06-identity-sync, contracts/
// account.md "Stores", research R2): one value holding both tokens.

const _session = Session(
  playerId: '0192f1c3-7d1e-7a4b-9c11-000000000001',
  access: 'access-token',
  refresh: 'refresh-token',
  accessExpiresAtMs: 1792627200000,
);

void main() {
  late Map<String, String> storage;

  setUp(() {
    storage = {};
    FlutterSecureStorage.setMockInitialValues(storage);
  });

  test('writes one value under wassal.session, holding both tokens', () async {
    await SecureSessionStore().write(_session);
    expect(storage.keys, ['wassal.session']);
    expect(jsonDecode(storage['wassal.session']!), {
      'player_id': _session.playerId,
      'access': 'access-token',
      'refresh': 'refresh-token',
      'access_expires_at_ms': 1792627200000,
    });
  });

  test('reads what it wrote, and clear removes it', () async {
    final store = SecureSessionStore();
    expect(await store.read(), isNull);
    await store.write(_session);
    final read = (await store.read())!;
    expect(read.playerId, _session.playerId);
    expect(read.access, 'access-token');
    expect(read.refresh, 'refresh-token');
    expect(read.accessExpiresAtMs, 1792627200000);

    await store.clear();
    expect(await store.read(), isNull);
    expect(storage, isEmpty);
  });

  test('a corrupted value reads as null', () async {
    for (final junk in [
      'not json',
      '[]',
      '{"player_id": "p", "access": "a"}',
      '{"player_id": "p", "access": "a", "refresh": "r", '
          '"access_expires_at_ms": 1.5}',
    ]) {
      storage['wassal.session'] = junk;
      expect(await SecureSessionStore().read(), isNull, reason: junk);
    }
  });

  test('prints only the player', () {
    expect(_session.toString(), isNot(contains('access-token')));
    expect(_session.toString(), isNot(contains('refresh-token')));
    expect(_session.toString(), contains(_session.playerId));
  });

  test('iOS: this device only, never synchronized', () {
    final options = SecureSessionStore.storage.iOptions.toMap();
    expect(options['accessibility'], 'first_unlock_this_device');
    expect(options['synchronizable'], 'false');
  });

  test('Android: no namespace, so the four excluded files; reset on '
      'error', () {
    final options = SecureSessionStore.storage.aOptions.toMap();
    expect(options['storageNamespace'], '');
    expect(options['preferencesKeyPrefix'], '');
    expect(options['resetOnError'], 'true');
  });
}
