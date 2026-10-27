// What the player is told of the server (specs/011-m06-identity-sync,
// contracts/server-states.md, data-model.md "State transitions", research
// R17–R19): whether it can be reached, maintenance, and the update state.
// Memory only, but for the dismissed optional version.
import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wassal/bootstrap/startup.dart';
import 'package:wassal/core/content/client_version.dart';
import 'package:wassal/core/network/api_client.dart';
import 'package:wassal/core/platform/app_info.dart';
import 'package:wassal/core/platform/connectivity.dart';
import 'package:wassal/core/sync/bootstrap_service.dart';
import 'package:wassal/core/sync/domain/pass.dart';
import 'package:wassal/core/sync/domain/wire/bootstrap.dart';
import 'package:wassal/core/sync/domain/wire/iso_time.dart';
import 'package:wassal/core/sync/domain/wire/reader.dart';
import 'package:wassal/core/sync/sync_engine.dart' show SyncStatusSink;

part 'server_status.g.dart';

/// The optional update the player closed, in the preference store: not a
/// secret, and shown once per version (R18).
const dismissedUpdateKey = 'update.dismissedVersion';

enum Reach { online, offline }

/// `503 maintenance` (R19), with its end when `details.until` gave one.
final class Maintenance {
  const Maintenance({this.untilMs});

  final int? untilMs;

  @override
  bool operator ==(Object other) =>
      other is Maintenance && other.untilMs == untilMs;

  @override
  int get hashCode => untilMs.hashCode;

  @override
  String toString() => 'Maintenance($untilMs)';
}

sealed class UpdateState {
  const UpdateState();
}

final class NoUpdate extends UpdateState {
  const NoUpdate();

  @override
  bool operator ==(Object other) => other is NoUpdate;

  @override
  int get hashCode => 0;
}

final class OptionalUpdate extends UpdateState {
  const OptionalUpdate(this.latestVersion);

  final String latestVersion;

  @override
  bool operator ==(Object other) =>
      other is OptionalUpdate && other.latestVersion == latestVersion;

  @override
  int get hashCode => latestVersion.hashCode;

  @override
  String toString() => 'OptionalUpdate($latestVersion)';
}

/// Until the process ends, so a launch with no network plays on (Q2).
final class ForcedUpdate extends UpdateState {
  const ForcedUpdate();

  @override
  bool operator ==(Object other) => other is ForcedUpdate;

  @override
  int get hashCode => 1;
}

final class ServerStatusState {
  const ServerStatusState({
    this.reach = Reach.online,
    this.maintenance,
    this.update = const NoUpdate(),
  });

  final Reach reach;
  final Maintenance? maintenance;
  final UpdateState update;

  ServerStatusState copyWith({
    Reach? reach,
    Maintenance? Function()? maintenance,
    UpdateState? update,
  }) => ServerStatusState(
    reach: reach ?? this.reach,
    maintenance: maintenance == null ? this.maintenance : maintenance(),
    update: update ?? this.update,
  );
}

/// Hands every answer to [_observe] on its way back: [ServerStatus] sees
/// the account's, the bootstrap's and the sync's calls alike.
final class ObservedApiClient implements ApiClient {
  ObservedApiClient(this._inner, this._observe);

  final ApiClient _inner;
  final void Function(ApiResult result) _observe;

  @override
  Future<ApiResult> send(ApiRequest request) async {
    final result = await _inner.send(request);
    _observe(result);
    return result;
  }
}

@Riverpod(keepAlive: true)
class ServerStatus extends _$ServerStatus
    implements SyncStatusSink, ClientBlockSink {
  bool _linkUp = true;

  /// A bootstrap answered in this session (R17). A later failure keeps it:
  /// the bootstrap is spaced (R15), so the next one may be minutes away.
  bool _bootstrapped = false;

  @override
  ServerStatusState build() {
    final connectivity = ref.watch(connectivitySourceProvider);
    final changes = connectivity.online.listen(_link);
    ref.onDispose(() => unawaited(changes.cancel()));
    // The stream tells changes only: start from the current link.
    unawaited(
      connectivity.isOnline().then((up) {
        if (ref.mounted) _link(up);
      }),
    );
    return const ServerStatusState();
  }

  /// Every answer of the player's endpoints and the auth calls.
  void observe(ApiResult result) {
    switch (result) {
      case ApiUnreachable():
        unreachable();
      case ApiFailure(status: 503, code: 'maintenance', :final details):
        maintenance(details);
      case ApiFailure(status: 426):
        clientOutdated();
      case ApiFailure() || ApiOk():
        break;
    }
  }

  @override
  void reached() {}

  @override
  void unreachable() {
    if (state.reach != Reach.offline) {
      state = state.copyWith(reach: Reach.offline);
    }
  }

  @override
  void maintenance(Map<String, Object?> details) => state = state.copyWith(
    maintenance: () => Maintenance(untilMs: _until(details['until'])),
  );

  @override
  void clientOutdated() => state = state.copyWith(update: const ForcedUpdate());

  /// The sync's pass ended. One with no network failure clears maintenance,
  /// and brings reach back once a bootstrap has answered.
  @override
  void passEnded(PassOutcome outcome) {
    if (outcome is! PassDone && outcome is! PassIdle) return;
    state = state.copyWith(
      maintenance: () => null,
      reach: _bootstrapped && _linkUp ? Reach.online : null,
    );
  }

  /// A live bootstrap's `client` block: the bootstrap succeeded.
  @override
  void client(ClientBlock block) {
    _bootstrapped = true;
    if (state.update is ForcedUpdate) return;
    if (block.forceUpdate) {
      state = state.copyWith(update: const ForcedUpdate());
      return;
    }
    state = state.copyWith(update: _optional(block.latestVersion));
  }

  /// Closes an optional update, for its version.
  Future<void> dismiss() async {
    final update = state.update;
    if (update is! OptionalUpdate) return;
    state = state.copyWith(update: const NoUpdate());
    await ref
        .read(settingsStoreProvider)
        .requireValue
        .writeString(dismissedUpdateKey, update.latestVersion);
  }

  void _link(bool up) {
    _linkUp = up;
    if (!up) unreachable();
  }

  UpdateState _optional(String latestText) {
    final latest = ClientVersion.parse(latestText);
    final appText = ref.read(appInfoProvider).value?.version;
    final app = appText == null ? null : ClientVersion.parse(appText);
    final dismissed = ref
        .read(settingsStoreProvider)
        .value
        ?.readString(dismissedUpdateKey);
    if (latest == null || app == null || latest.compareTo(app) <= 0) {
      return const NoUpdate();
    }
    if (dismissed == latestText) return const NoUpdate();
    return OptionalUpdate(latestText);
  }

  static int? _until(Object? value) {
    if (value is! String) return null;
    try {
      return isoToMs(value);
    } on WireFormatException {
      return null;
    }
  }
}

/// «محتاج نت» for later features (FR-032).
@Riverpod(keepAlive: true)
bool isOnline(Ref ref) => ref.watch(serverStatusProvider).reach == Reach.online;
