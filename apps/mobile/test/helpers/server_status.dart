import 'package:wassal/core/network/api_client.dart';
import 'package:wassal/core/platform/store_launcher.dart';
import 'package:wassal/core/sync/domain/pass.dart';
import 'package:wassal/core/sync/domain/wire/bootstrap.dart';
import 'package:wassal/core/sync/server_status.dart';

/// The server states where a test puts them: every input is ignored, and
/// [pin] changes them. `dismiss` is the real one.
final class PinnedServerStatus extends ServerStatus {
  PinnedServerStatus([this._pinned = const ServerStatusState()]);

  final ServerStatusState _pinned;

  @override
  ServerStatusState build() => _pinned;

  void pin(ServerStatusState pinned) => state = pinned;

  @override
  void observe(ApiResult result) {}

  @override
  void unreachable() {}

  @override
  void maintenance(Map<String, Object?> details) {}

  @override
  void clientOutdated() {}

  @override
  void passEnded(PassOutcome outcome) {}

  @override
  void client(ClientBlock block) {}
}

/// A store listing that records its openings.
final class FakeStoreLauncher implements StoreLauncher {
  FakeStoreLauncher({this.hasListing = true});

  @override
  final bool hasListing;

  int opened = 0;

  @override
  Future<bool> openListing() async {
    opened++;
    return true;
  }
}
