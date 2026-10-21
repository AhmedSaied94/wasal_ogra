// Checking for and downloading new packs
// (specs/006-m04-content-loader/contracts/updates.md "When a check runs",
// "One check").
import 'dart:async';
import 'dart:io';

import 'package:content_models/content_models.dart';
import 'package:dio/dio.dart' show CancelToken;
import 'package:wassal/bootstrap/flavor.dart';
import 'package:wassal/core/content/client_version.dart';
import 'package:wassal/core/content/content_providers.dart';
import 'package:wassal/core/content/content_remote.dart';
import 'package:wassal/core/content/decode_pack_file.dart';
import 'package:wassal/core/content/pack_content_source.dart';
import 'package:wassal/core/content/pack_store.dart';
import 'package:wassal/core/content/refusal_reason.dart';
import 'package:wassal/core/network/api_environment.dart';
import 'package:wassal/core/network/http_client.dart' show downloadMaxBytes;
import 'package:wassal/core/platform/clock.dart';

/// Runs at most one manifest check at a time, and downloads a newer pack
/// into the store as `ready`. It never switches packs: the controller does,
/// at launch or on arrival at Home.
final class ContentUpdater {
  ContentUpdater({
    required this._remote,
    required this._store,
    required this._decode,
    required this._flavor,
    required this._appVersion,
    required this._clock,
    required this._activeVersion,
    required this._readyVersion,
    required this._acceptReady,
  });

  /// The least time between two checks (FR-015).
  static const throttle = Duration(minutes: 15);

  final ContentRemote _remote;
  final PackStore _store;
  final PackDecoder _decode;
  final Flavor _flavor;
  final ClientVersion? _appVersion;
  final Clock _clock;
  final int Function() _activeVersion;
  final int? Function() _readyVersion;
  final void Function(PackContentSource source) _acceptReady;

  bool _started = false;
  bool _foreground = true;
  bool _online = true;
  ({CancelToken cancel, Future<void> done})? _running;

  /// Startup has completed: check now.
  Future<void> start() {
    _started = true;
    return check();
  }

  Future<void> onResume() {
    _foreground = true;
    return check();
  }

  /// The app was paused, hidden or detached: cancel the running check.
  void onBackground() {
    _foreground = false;
    _running?.cancel.cancel();
  }

  /// Only a change from offline to online triggers a check.
  Future<void> onConnectivity(bool online) {
    final cameBack = online && !_online;
    _online = online;
    return cameBack ? check() : Future.value();
  }

  void dispose() => _running?.cancel.cancel();

  /// Checks the manifest, and downloads a newer pack. [force] skips only the
  /// 15-minute throttle (M06, when bootstrap reports a newer version).
  Future<void> check({bool force = false}) async {
    if (!_started || !_foreground) return;
    if (_running case (:final cancel, :final done)?) {
      // One check at a time. One that leaving the foreground cancelled may
      // still be unwinding, so a quick resume waits for it, then checks.
      if (!cancel.isCancelled) return;
      await done;
      return check(force: force);
    }
    final now = _clock();
    final previous = _store.state.lastCheckAt;
    if (!force &&
        previous != null &&
        !previous.isAfter(now) &&
        now.difference(previous) < throttle) {
      return;
    }
    final cancel = CancelToken();
    final finished = Completer<void>();
    _running = (cancel: cancel, done: finished.future);
    int? downloading;
    try {
      _store.markChecked(now);
      final entry = await _newEntry(cancel, previous);
      if (entry == null) return;
      downloading = entry.version;
      await _download(entry, cancel, previous);
    } on FileSystemException {
      if (downloading != null) _discard(downloading);
      _record(RefusalReason.storageError, version: downloading);
    } finally {
      _running = null;
      finished.complete();
    }
  }

  /// Steps 2 and 3: the manifest's acceptable `core` entry, if one is new.
  Future<ManifestPack?> _newEntry(
    CancelToken cancel,
    DateTime? previous,
  ) async {
    switch (await _remote.fetchManifest(cancel: cancel)) {
      case ManifestCancelled():
        _store.restoreChecked(previous);
        return null;
      case ManifestFailed(:final detail):
        _record(RefusalReason.manifestFailed, detail: detail);
        return null;
      case ManifestOk(:final manifest):
        return _accept(manifest);
    }
  }

  /// data-model.md "Manifest entry", rules 1 to 6.
  ManifestPack? _accept(Manifest manifest) {
    if (manifest.version == 0) return null;
    final cores = manifest.packs.where((p) => p.packId == 'core').toList()
      ..sort((a, b) => b.version.compareTo(a.version));
    if (cores.isEmpty) return null;
    final entry = cores.first;
    final v = entry.version;
    final ready = _readyVersion() ?? _store.state.ready?.version ?? 0;
    if (v <= _activeVersion() || v <= ready) return null;
    if (entry.size > downloadMaxBytes) {
      _record(RefusalReason.tooLarge, version: v);
      return null;
    }
    final minimum = ClientVersion.parse(entry.minClientVersion);
    final app = _appVersion;
    if (minimum == null || app == null || !app.atLeast(minimum)) {
      return _ignore(v, RefusalDetail.minClientVersion);
    }
    if (_store.state.unusable.containsKey(v)) {
      return _ignore(v, RefusalDetail.unusable);
    }
    final url = Uri.tryParse(entry.url);
    if (url == null || !isAllowedUrl(_flavor, url)) {
      return _ignore(v, RefusalDetail.insecureUrl);
    }
    return entry;
  }

  ManifestPack? _ignore(int version, RefusalDetail detail) {
    _record(RefusalReason.entryIgnored, version: version, detail: detail);
    return null;
  }

  /// Steps 4 to 6: download, check, and keep as the ready pack.
  Future<void> _download(
    ManifestPack entry,
    CancelToken cancel,
    DateTime? previous,
  ) async {
    final v = entry.version;
    final part = _store.beginDownload(v);
    switch (await _remote.download(entry, part, cancel: cancel)) {
      case DownloadCancelled():
        // Not a failure, and not a check: the next resume checks at once.
        _discard(v);
        _store.restoreChecked(previous);
        return;
      case DownloadFailed(:final reason, :final detail):
        _discard(v);
        _record(reason, version: v, detail: detail);
        return;
      case Downloaded():
        break;
    }
    final expected = ExpectedPack(
      version: v,
      size: entry.size,
      sha256: entry.sha256,
      minClientVersion: entry.minClientVersion,
    );
    switch (await _decode(part.readAsBytesSync(), expected)) {
      case PackRefused(:final reason):
        _discard(v);
        _record(reason, version: v);
      case PackDecoded(:final source):
        _store.commitDownload(v, expected);
        _acceptReady(source);
    }
  }

  void _discard(int version) {
    try {
      _store.discardDownload(version);
    } on FileSystemException {
      // The next launch's reconcile removes tmp/.
    }
  }

  void _record(RefusalReason reason, {int? version, RefusalDetail? detail}) {
    try {
      _store.recordFailure(reason, version: version, detail: detail);
    } on FileSystemException {
      // Nothing can be written; the event is lost, the pack isn't.
    }
  }
}
