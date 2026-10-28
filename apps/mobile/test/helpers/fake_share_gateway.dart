import 'dart:async';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:wassal/core/platform/share_gateway.dart';

/// One picture offered to the share sheet.
typedef SharedImage = ({
  Uint8List png,
  String fileName,
  String? text,
  Rect? origin,
});

/// Keeps what it is given; [hold] keeps the sheet open until [release],
/// and [failWith] makes the next share throw.
final class FakeShareGateway implements ShareGateway {
  final shared = <SharedImage>[];

  /// Called on each share, before it completes.
  int calls = 0;

  Object? failWith;
  Completer<void>? _held;

  void hold() => _held = Completer<void>();

  void release() => _held?.complete();

  @override
  Future<void> shareImage(
    Uint8List png, {
    required String fileName,
    String? text,
    Rect? origin,
  }) async {
    calls++;
    if (failWith case final error?) {
      failWith = null;
      throw error;
    }
    shared.add((png: png, fileName: fileName, text: text, origin: origin));
    await _held?.future;
  }
}
