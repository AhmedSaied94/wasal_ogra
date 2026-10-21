import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wassal/bootstrap/flavor.dart';
import 'package:wassal/core/config/config_providers.dart';
import 'package:wassal/core/content/bundled_pack.dart';
import 'package:wassal/core/content/client_version.dart';
import 'package:wassal/core/content/content_providers.dart';
import 'package:wassal/core/content/content_state.dart';
import 'package:wassal/core/content/decode_pack_file.dart';
import 'package:wassal/core/content/domain/content_source.dart';
import 'package:wassal/core/content/pack_content_source.dart';
import 'package:wassal/core/content/pack_store.dart';
import 'package:wassal/core/content/refusal_reason.dart';
import 'package:wassal/core/platform/app_info.dart';

part 'content_controller.g.dart';

enum ContentOrigin { bundled, stored }

/// The pack in use (data-model.md "Active content").
@immutable
final class ActiveContent {
  const ActiveContent({
    required this.version,
    required this.origin,
    required this.source,
  });

  final int version;
  final ContentOrigin origin;
  final ContentSource source;

  @override
  String toString() => 'ActiveContent(v$version, ${origin.name})';
}

/// No pack passed its checks at launch, not even the bundled one (FR-008).
/// Startup fails, and the boot screen offers its retry.
final class ContentUnavailable implements Exception {
  const ContentUnavailable(this.message);

  final String message;

  @override
  String toString() => 'ContentUnavailable: $message';
}

/// Chooses the active pack at launch, holds the ready pack, and switches to
/// it at Home (specs/006-m04-content-loader/contracts/loading.md "Launch",
/// contracts/updates.md "The switch at Home").
@Riverpod(keepAlive: true, name: 'activeContentProvider')
class ContentController extends _$ContentController {
  late PackStore _store;
  PackContentSource? _ready;

  /// The version of the verified pack waiting for a switch, if any.
  int? get readyVersion => _ready?.version;

  @override
  Future<ActiveContent> build() async {
    final watch = Stopwatch()..start();
    _ready = null;
    _store = await ref.read(packStoreProvider.future);
    final app = await ref.read(appInfoProvider.future);
    _guard(() {
      _store
        ..reconcile()
        ..setAppVersion(app.versionWithBuild);
    });
    final active = await _choose(ClientVersion.parse(app.versionWithBuild));
    _logActive(active, watch.elapsed);
    return active;
  }

  /// Highest version first, the first that passes wins (research R6). On a
  /// tie the bundled pack goes first: it needs no file read.
  Future<ActiveContent> _choose(ClientVersion? app) async {
    final decode = ref.read(packDecoderProvider);
    final bundled = await _bundled();
    final candidates = <(int, StoredPack?)>[
      if (bundled != null) (bundled.record.version, null),
      for (final entry in _store.state.stored)
        if (_fits(entry, app)) (entry.version, entry),
    ]..sort((a, b) => a.$1 != b.$1 ? b.$1 - a.$1 : (a.$2 == null ? -1 : 1));

    for (final (version, entry) in candidates) {
      if (entry == null) {
        final result = await decode(bundled!.bytes, bundled.record.expected);
        switch (result) {
          case PackDecoded(:final source):
            _guard(_store.dropStored);
            return ActiveContent(
              version: version,
              origin: ContentOrigin.bundled,
              source: source,
            );
          case PackRefused(:final reason):
            _guard(
              () => _store.recordFailure(
                RefusalReason.bundledCheckFailed,
                version: version,
                cause: reason,
              ),
            );
        }
      } else {
        switch (await _decodeStored(decode, entry)) {
          case PackDecoded(:final source):
            if (entry.state == StoredState.ready) {
              _guard(() => _store.activate(version));
            }
            return ActiveContent(
              version: version,
              origin: ContentOrigin.stored,
              source: source,
            );
          case PackRefused(:final reason):
            // Not an attempt and not unusable: the next check downloads it
            // again (spec US3-7).
            _guard(() {
              _store
                ..recordFailure(
                  RefusalReason.storedCheckFailed,
                  version: version,
                  cause: reason,
                )
                ..removeStored(version);
            });
        }
      }
    }
    throw ContentUnavailable(
      bundled == null
          ? 'no bundled pack, and no stored pack passed its check'
          : 'no pack passed its check, the bundled one included',
    );
  }

  Future<BundledPack?> _bundled() async {
    try {
      return await loadBundledPack(
        ref.read(assetBytesReaderProvider),
        ref.read(flavorProvider),
      );
    } on BundledPackMissing {
      return null;
    } on BundledPackInvalid {
      return null;
    }
  }

  Future<PackDecodeResult> _decodeStored(
    PackDecoder decode,
    StoredPack entry,
  ) async {
    try {
      return await decode(_store.readPack(entry.version), entry.expected);
    } on FileSystemException {
      return const PackRefused(RefusalReason.storageError);
    }
  }

  /// Holds a verified download in memory until the next arrival at Home
  /// (research R7). A newer one replaces it.
  void acceptReady(PackContentSource source) {
    final current = _ready;
    if (current == null || source.version > current.version) _ready = source;
  }

  /// Switches to the ready pack, if any, in one state change, and records it
  /// as active in the same step, so a download committed right after can't
  /// take it for an older ready pack. Only deleting the old file waits until
  /// after the frame. A failure is recorded, and the next launch cleans up.
  Future<void> switchIfReady() async {
    final ready = _ready;
    if (ready == null) return;
    _ready = null;
    state = AsyncData(
      ActiveContent(
        version: ready.version,
        origin: ContentOrigin.stored,
        source: ready,
      ),
    );
    _guard(() => _store.markActive(ready.version));
    await Future<void>(() => _guard(_store.removeUnlisted));
  }

  /// Runs a store operation. The disk may be full or read-only: that is
  /// recorded if it can be, and the app goes on with what it has in memory.
  void _guard(void Function() operation) {
    try {
      operation();
    } on FileSystemException {
      try {
        _store.recordFailure(RefusalReason.storageError);
      } on FileSystemException {
        // Nothing more can be written; the next launch reconciles.
      }
    }
  }
}

bool _fits(StoredPack entry, ClientVersion? app) {
  final minimum = ClientVersion.parse(entry.minClientVersion);
  return app != null && minimum != null && app.atLeast(minimum);
}

/// Shows in `flutter logs` for the load-time check (research R15). Release
/// builds print nothing.
void _logActive(ActiveContent active, Duration elapsed) {
  if (kDebugMode || kProfileMode) {
    debugPrint(
      'content: active v${active.version} (${active.origin.name}) '
      'in ${elapsed.inMilliseconds} ms',
    );
  }
}
