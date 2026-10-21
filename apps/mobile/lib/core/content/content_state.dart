// The app's record of the packs it stores: `<app support>/content/state.json`
// (specs/006-m04-content-loader/data-model.md "Content state"). Only
// PackStore writes it.
import 'dart:convert';

import 'package:content_models/content_models.dart';
import 'package:flutter/foundation.dart';
import 'package:wassal/core/content/decode_pack_file.dart';

/// The only `format` this app reads. Any other counts as an empty state.
const contentStateFormat = 1;

/// How many events `state.json` keeps, newest last.
const maxContentEvents = 20;

enum StoredState {
  /// Verified, waiting for a switch: the spec's "verified next pack".
  ready,

  /// The pack in use.
  active,
}

/// A pack file in the content directory, with the values every later check
/// uses (data-model.md "Stored pack").
@immutable
final class StoredPack {
  const StoredPack({
    required this.version,
    required this.size,
    required this.sha256,
    required this.minClientVersion,
    required this.state,
  });

  final int version;
  final int size;
  final String sha256;
  final String minClientVersion;
  final StoredState state;

  String get file => 'core-$version.json.gz';

  ExpectedPack get expected => ExpectedPack(
    version: version,
    size: size,
    sha256: sha256,
    minClientVersion: minClientVersion,
  );

  StoredPack withState(StoredState state) => StoredPack(
    version: version,
    size: size,
    sha256: sha256,
    minClientVersion: minClientVersion,
    state: state,
  );

  Map<String, Object> toJson() => {
    'version': version,
    'file': file,
    'size': size,
    'sha256': sha256,
    'min_client_version': minClientVersion,
    'state': state.name,
  };

  factory StoredPack.fromJson(Map<String, Object?> json) {
    final version = json['version']! as int;
    if (version < 1 || json['file'] != 'core-$version.json.gz') {
      throw FormatException('bad stored entry for v$version');
    }
    return StoredPack(
      version: version,
      size: json['size']! as int,
      sha256: json['sha256']! as String,
      minClientVersion: json['min_client_version']! as String,
      state: StoredState.values.byName(json['state']! as String),
    );
  }
}

/// One refusal or failure, as M15 will report it. No URL, header or content.
@immutable
final class ContentEvent {
  const ContentEvent({
    required this.at,
    required this.reason,
    this.version,
    this.detail,
  });

  final DateTime at;

  /// A `RefusalReason` wire code.
  final String reason;
  final int? version;

  /// A `RefusalDetail` wire code, or for `stored_check_failed` and
  /// `bundled_check_failed`, the decoder's reason.
  final String? detail;

  Map<String, Object> toJson() => {
    'at': at.toUtc().toIso8601String(),
    'reason': reason,
    'version': ?version,
    'detail': ?detail,
  };

  factory ContentEvent.fromJson(Map<String, Object?> json) => ContentEvent(
    at: _utc(json['at']! as String),
    reason: json['reason']! as String,
    version: json['version'] as int?,
    detail: json['detail'] as String?,
  );
}

@immutable
final class ContentState {
  const ContentState({
    this.appVersion,
    this.stored = const [],
    this.unusable = const {},
    this.attempts = const {},
    this.lastCheckAt,
    this.events = const [],
  });

  static const empty = ContentState();

  /// `<version>+<build>` of the app that last wrote this state.
  final String? appVersion;

  /// At most one `active` and one `ready` entry.
  final List<StoredPack> stored;

  /// Versions this app version won't download again, with the reason.
  final Map<int, String> unusable;

  /// Failed size or sha256 checks per version: 1 or 2.
  final Map<int, int> attempts;

  /// The last manifest check, failed or not. Always UTC.
  final DateTime? lastCheckAt;

  /// The last [maxContentEvents], oldest first.
  final List<ContentEvent> events;

  StoredPack? get active => _withState(StoredState.active);
  StoredPack? get ready => _withState(StoredState.ready);

  StoredPack? _withState(StoredState state) {
    for (final entry in stored) {
      if (entry.state == state) return entry;
    }
    return null;
  }

  ContentState copyWith({
    String? appVersion,
    List<StoredPack>? stored,
    Map<int, String>? unusable,
    Map<int, int>? attempts,
    List<ContentEvent>? events,
  }) => ContentState(
    appVersion: appVersion ?? this.appVersion,
    stored: stored ?? this.stored,
    unusable: unusable ?? this.unusable,
    attempts: attempts ?? this.attempts,
    lastCheckAt: lastCheckAt,
    events: events ?? this.events,
  );

  /// This state with [at] as the last check, or none when [at] is null.
  ContentState withLastCheckAt(DateTime? at) => ContentState(
    appVersion: appVersion,
    stored: stored,
    unusable: unusable,
    attempts: attempts,
    lastCheckAt: at?.toUtc(),
    events: events,
  );

  Map<String, Object> toJson() => {
    'format': contentStateFormat,
    'app_version': ?appVersion,
    'stored': [for (final entry in stored) entry.toJson()],
    'unusable': [
      for (final MapEntry(key: version, value: reason) in unusable.entries)
        {'version': version, 'reason': reason},
    ],
    'attempts': [
      for (final MapEntry(key: version, value: count) in attempts.entries)
        {'version': version, 'count': count},
    ],
    'last_check_at': ?lastCheckAt?.toUtc().toIso8601String(),
    'events': [for (final event in events) event.toJson()],
  };

  Uint8List encode() => utf8.encode(canonicalJson(toJson()));

  /// The state in [bytes], or [empty] for anything this app can't read: a
  /// damaged file, another `format`, or a rule broken.
  static ContentState decode(Uint8List bytes) {
    try {
      final json = decodeContentJson(utf8.decode(bytes));
      if (json['format'] != contentStateFormat) return empty;
      final stored = [
        for (final entry in json['stored']! as List<Object?>)
          StoredPack.fromJson(_map(entry)),
      ];
      final states = stored.map((e) => e.state).toList();
      if (stored.length > 2 || states.toSet().length != states.length) {
        return empty;
      }
      return ContentState(
        appVersion: json['app_version'] as String?,
        stored: List.unmodifiable(stored),
        unusable: Map.unmodifiable({
          for (final entry in json['unusable']! as List<Object?>)
            _map(entry)['version']! as int: _map(entry)['reason']! as String,
        }),
        attempts: Map.unmodifiable({
          for (final entry in json['attempts']! as List<Object?>)
            _map(entry)['version']! as int: _map(entry)['count']! as int,
        }),
        lastCheckAt: switch (json['last_check_at']) {
          final String at => _utc(at),
          _ => null,
        },
        events: List.unmodifiable([
          for (final entry in json['events']! as List<Object?>)
            ContentEvent.fromJson(_map(entry)),
        ]),
      );
      // A damaged record is a normal case here, not a bug: R5 says it counts
      // as empty, whatever is wrong with it.
    } catch (_) {
      return empty;
    }
  }
}

Map<String, Object?> _map(Object? value) => (value! as Map<String, Object?>);

DateTime _utc(String text) {
  final at = DateTime.parse(text);
  if (!at.isUtc) throw FormatException('not UTC: $text');
  return at;
}
