import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'clock.g.dart';

/// The current time. Tests inject a fixed or stepped one.
typedef Clock = DateTime Function();

@Riverpod(keepAlive: true)
Clock clock(Ref ref) => DateTime.now;
