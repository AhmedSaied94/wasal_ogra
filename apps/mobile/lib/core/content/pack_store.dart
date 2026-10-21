// The content directory: stored packs, downloads in progress and
// state.json (specs/006-m04-content-loader/contracts/loading.md "PackStore").
//
// The file APIs are synchronous on purpose: the files are small, the calls
// are few, and widget tests (which run in fake async) can drive the real
// store on a temp directory.
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wassal/core/content/content_state.dart';
import 'package:wassal/core/content/decode_pack_file.dart';
import 'package:wassal/core/content/refusal_reason.dart';
import 'package:wassal/core/platform/clock.dart';

part 'pack_store.g.dart';

/// The moments a kill must not corrupt anything (contracts/loading.md
/// "Kill points"). Tests throw from [PackStore.onKillPoint] at each one.
enum KillPoint {
  /// After the last chunk, before the flush.
  partWritten,

  /// After the flush, before the rename.
  partFlushed,

  /// After the rename, before `state.json` is written.
  renamed,

  /// After `state.json`, before the superseded file is deleted.
  stateWritten,

  /// After `activate`'s `state.json`, before the old active file is deleted.
  activateStateWritten,
}

/// How many size or sha256 failures of one version make it unusable.
const maxChecksumAttempts = 3;

/// The decoder refusals that make a version unusable at once (research R14).
const _unusableAtOnce = {
  RefusalReason.decompressTooLarge,
  RefusalReason.unreadable,
  RefusalReason.wrongIdentity,
  RefusalReason.schemaUnsupported,
};

/// The only writer of the content directory. Every `state.json` write is
/// atomic, files are renamed into place only when complete, and files are
/// deleted only after the `state.json` that drops them is written.
final class PackStore {
  PackStore(this.dir, {this._clock = DateTime.now, this.onKillPoint});

  final Directory dir;
  final Clock _clock;
  final void Function(KillPoint point)? onKillPoint;

  ContentState _state = ContentState.empty;

  /// The state as last read or written.
  ContentState get state => _state;

  File get _stateFile => File('${dir.path}/state.json');
  File get _stateTmp => File('${dir.path}/state.json.tmp');
  Directory get _tmp => Directory('${dir.path}/tmp');

  File packFile(int version) => File('${dir.path}/core-$version.json.gz');
  File partFile(int version) => File('${_tmp.path}/core-$version.part');

  /// Reads `state.json`, then makes the directory match it: `tmp/` and
  /// unlisted pack files go, and entries whose file is missing are dropped.
  void reconcile() {
    dir.createSync(recursive: true);
    _state = _stateFile.existsSync()
        ? ContentState.decode(_stateFile.readAsBytesSync())
        : ContentState.empty;
    if (_tmp.existsSync()) _tmp.deleteSync(recursive: true);
    if (_stateTmp.existsSync()) _stateTmp.deleteSync();
    final kept = [
      for (final entry in _state.stored)
        if (packFile(entry.version).existsSync()) entry,
    ];
    _deleteFiles(except: {for (final entry in kept) entry.file});
    if (kept.length != _state.stored.length) {
      _write(_state.copyWith(stored: kept));
    }
  }

  /// Deletes every pack file state.json doesn't list.
  void removeUnlisted() =>
      _deleteFiles(except: {for (final entry in _state.stored) entry.file});

  void _deleteFiles({required Set<String> except}) {
    for (final file in dir.listSync().whereType<File>()) {
      final name = file.uri.pathSegments.last;
      if (_isPackFile(name) && !except.contains(name)) file.deleteSync();
    }
  }

  /// Records [appVersion]. A new app version or build clears the unusable
  /// list and the attempts (FR-023).
  void setAppVersion(String appVersion) {
    if (_state.appVersion == appVersion) return;
    _write(_state.copyWith(appVersion: appVersion, unusable: {}, attempts: {}));
  }

  /// The bytes of a stored pack.
  Uint8List readPack(int version) => packFile(version).readAsBytesSync();

  /// The empty part file a download of [version] writes to.
  File beginDownload(int version) {
    _tmp.createSync(recursive: true);
    final part = partFile(version);
    if (part.existsSync()) part.deleteSync();
    return part;
  }

  /// Deletes a download's part file, if any.
  void discardDownload(int version) {
    final part = partFile(version);
    if (part.existsSync()) part.deleteSync();
  }

  /// Moves a verified download into place as the `ready` pack, then deletes
  /// the older ready pack's file, if any.
  void commitDownload(int version, ExpectedPack expected) {
    final part = partFile(version);
    _kill(KillPoint.partWritten);
    part.openSync(mode: FileMode.append)
      ..flushSync()
      ..closeSync();
    _kill(KillPoint.partFlushed);
    part.renameSync(packFile(version).path);
    _kill(KillPoint.renamed);
    final older = _state.ready;
    final attempts = {..._state.attempts}..remove(version);
    _write(
      _state.copyWith(
        stored: [
          ?_state.active,
          StoredPack(
            version: version,
            size: expected.size,
            sha256: expected.sha256,
            minClientVersion: expected.minClientVersion,
            state: StoredState.ready,
          ),
        ],
        attempts: attempts,
      ),
    );
    _kill(KillPoint.stateWritten);
    if (older != null && older.version != version) {
      _deleteUnlisted(packFile(older.version));
    }
  }

  /// Makes stored [version] the active pack, then deletes the old active
  /// pack's file. Does nothing for a version the store doesn't hold.
  void activate(int version) {
    final old = _state.active;
    if (markActive(version) && old != null) {
      _deleteUnlisted(packFile(old.version));
    }
  }

  /// [activate]'s state write alone. The old active pack's file stays,
  /// unlisted, until [removeUnlisted] or the next launch. Returns whether
  /// anything changed.
  bool markActive(int version) {
    if (_state.active?.version == version) return false;
    final entry = _state.stored.where((e) => e.version == version).firstOrNull;
    if (entry == null) return false;
    _write(_state.copyWith(stored: [entry.withState(StoredState.active)]));
    _kill(KillPoint.activateStateWritten);
    return true;
  }

  /// Forgets every stored pack: the bundled one won at launch.
  void dropStored() {
    final files = [for (final entry in _state.stored) packFile(entry.version)];
    if (files.isEmpty) return;
    _write(_state.copyWith(stored: []));
    files.forEach(_deleteUnlisted);
  }

  /// Forgets stored [version], which failed its check at launch. It isn't
  /// marked unusable, so the next check downloads it again (spec US3-7).
  void removeStored(int version) {
    _write(
      _state.copyWith(
        stored: [
          for (final entry in _state.stored)
            if (entry.version != version) entry,
        ],
      ),
    );
    _deleteUnlisted(packFile(version));
  }

  void markChecked(DateTime at) => _write(_state.withLastCheckAt(at));

  /// Puts the last check time back after a cancelled check, which doesn't
  /// count toward the throttle (FR-015). Null removes it.
  void restoreChecked(DateTime? previous) =>
      _write(_state.withLastCheckAt(previous));

  /// Records a refusal or failure as an event. Size and sha256 mismatches
  /// count as attempts, and the third makes [version] unusable; decoder
  /// refusals make it unusable at once (research R14).
  ///
  /// [detail] is a request's detail; [cause] is the decoder reason behind
  /// a launch check failure.
  void recordFailure(
    RefusalReason reason, {
    int? version,
    RefusalDetail? detail,
    RefusalReason? cause,
  }) {
    final at = _clock().toUtc();
    final event = ContentEvent(
      at: at,
      reason: reason.wire,
      version: version,
      detail: detail?.wire ?? cause?.wire,
    );
    // A repeat of the newest event only moves its time, so an entry ignored
    // on every check can't push older events out of the last 20.
    final events = [..._state.events];
    if (events.lastOrNull case final last?
        when last.reason == event.reason &&
            last.version == event.version &&
            last.detail == event.detail) {
      events.removeLast();
    }
    events.add(event);
    var unusable = _state.unusable;
    var attempts = _state.attempts;
    if (version != null && reason.isAttempt) {
      final count = (attempts[version] ?? 0) + 1;
      attempts = {...attempts}..remove(version);
      if (count >= maxChecksumAttempts) {
        unusable = {...unusable, version: RefusalReason.checksumFailed.wire};
        events.add(
          ContentEvent(
            at: at,
            reason: RefusalReason.checksumFailed.wire,
            version: version,
          ),
        );
      } else {
        attempts[version] = count;
      }
    } else if (version != null && _unusableAtOnce.contains(reason)) {
      unusable = {...unusable, version: reason.wire};
      attempts = {...attempts}..remove(version);
    }
    developer.log(
      '${reason.wire} v$version ${detail?.wire ?? cause?.wire ?? ''}'.trim(),
      name: 'wassal.content',
    );
    _write(
      _state.copyWith(
        unusable: unusable,
        attempts: attempts,
        events: events.length > maxContentEvents
            ? events.sublist(events.length - maxContentEvents)
            : events,
      ),
    );
  }

  void _write(ContentState next) {
    _stateTmp.writeAsBytesSync(next.encode(), flush: true);
    _stateTmp.renameSync(_stateFile.path);
    _state = next;
  }

  void _kill(KillPoint point) => onKillPoint?.call(point);

  /// Deletes a file state.json no longer lists. A failure leaves it for the
  /// next launch's reconcile: the state is already right.
  void _deleteUnlisted(File file) {
    try {
      if (file.existsSync()) file.deleteSync();
    } on FileSystemException {
      // Reconciled at the next launch.
    }
  }
}

bool _isPackFile(String name) =>
    name.startsWith('core-') && name.endsWith('.json.gz');

/// The production store, in the app's private support directory (research
/// R5): the OS never evicts it, and other apps can't read it.
@Riverpod(keepAlive: true)
Future<PackStore> packStore(Ref ref) async {
  final support = await getApplicationSupportDirectory();
  return PackStore(
    Directory('${support.path}/content'),
    clock: ref.watch(clockProvider),
  );
}
