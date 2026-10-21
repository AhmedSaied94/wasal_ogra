import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'connectivity.g.dart';

/// Whether the device has a network connection. "Online" means a link is
/// up, not that the server answers: requests still fail and are retried.
abstract interface class ConnectivitySource {
  /// Emits on every change.
  Stream<bool> get online;

  Future<bool> isOnline();
}

/// [ConnectivitySource] over connectivity_plus.
final class ConnectivityPlusSource implements ConnectivitySource {
  ConnectivityPlusSource([Connectivity? connectivity])
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  @override
  Stream<bool> get online =>
      _connectivity.onConnectivityChanged.map(isOnlineResult);

  @override
  Future<bool> isOnline() async =>
      isOnlineResult(await _connectivity.checkConnectivity());
}

/// Any result other than `none` is a connection.
bool isOnlineResult(List<ConnectivityResult> results) =>
    results.any((result) => result != ConnectivityResult.none);

@Riverpod(keepAlive: true)
ConnectivitySource connectivitySource(Ref ref) => ConnectivityPlusSource();
