import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/economy/domain/trusted_time.dart';
import 'package:wassal/core/platform/uptime.dart';

// The `wassal/clock` channel, against a mock of MainActivity's handler.

const _channel = MethodChannel('wassal/clock');

void _reply(Object? Function(MethodCall call)? handler) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        _channel,
        handler == null ? null : (call) async => handler(call),
      );
  addTearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const source = ChannelUptimeSource();

  test('bootSnapshot gives the uptime counter and the boot count', () async {
    final calls = <String>[];
    _reply((call) {
      calls.add(call.method);
      return {'elapsed_realtime_ms': 123, 'boot_count': 7};
    });
    final snapshot = await source.snapshot();
    expect(calls, ['bootSnapshot']);
    expect(snapshot?.elapsedRealtimeMs, 123);
    expect(snapshot?.bootCount, 7);
  });

  test('a null boot count is kept as unknown', () async {
    _reply((_) => {'elapsed_realtime_ms': 123, 'boot_count': null});
    final snapshot = await source.snapshot();
    expect(snapshot, isA<BootSnapshot>());
    expect(snapshot?.elapsedRealtimeMs, 123);
    expect(snapshot?.bootCount, isNull);
  });

  group('no reading', () {
    test('without a handler (MissingPluginException)', () async {
      _reply(null);
      expect(await source.snapshot(), isNull);
    });

    test('when the handler fails (PlatformException)', () async {
      _reply((_) => throw PlatformException(code: 'unavailable'));
      expect(await source.snapshot(), isNull);
    });

    test('for a non-integer value', () async {
      _reply((_) => {'elapsed_realtime_ms': '123', 'boot_count': 7});
      expect(await source.snapshot(), isNull);
    });

    test('for a missing key', () async {
      _reply((_) => {'boot_count': 7});
      expect(await source.snapshot(), isNull);
    });

    test('for no map at all', () async {
      _reply((_) => null);
      expect(await source.snapshot(), isNull);
    });
  });
}
