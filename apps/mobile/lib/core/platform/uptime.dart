import 'package:flutter/services.dart';
import 'package:wassal/core/economy/domain/trusted_time.dart';

/// Reads the phone's uptime counter and boot count, which trusted time
/// counts with (specs/007-m05-local-economy/contracts/fuel-and-time.md).
abstract interface class UptimeSource {
  /// Null where the platform has no channel: iOS before phase 3, and tests
  /// without a fake.
  Future<BootSnapshot?> snapshot();
}

/// The `wassal/clock` channel in `MainActivity`.
final class ChannelUptimeSource implements UptimeSource {
  const ChannelUptimeSource();

  static const _channel = MethodChannel('wassal/clock');

  @override
  Future<BootSnapshot?> snapshot() async {
    final Map<String, Object?>? reply;
    try {
      reply = await _channel.invokeMapMethod<String, Object?>('bootSnapshot');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
    return switch (reply) {
      {
        'elapsed_realtime_ms': final int elapsed,
        'boot_count': final int? boot,
      } =>
        BootSnapshot(elapsedRealtimeMs: elapsed, bootCount: boot),
      _ => null,
    };
  }
}
