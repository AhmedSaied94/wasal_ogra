import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_source.dart';

// Domain folders are pure Dart (constitution I): no Flutter, no plugin and no
// dart:io, so their rules run anywhere and stay deterministic. Each folder
// lists what it may import.

/// The content domain: the generated models only
/// (specs/006-m04-content-loader/contracts/content-source.md).
bool _contentAllowed(String uri) =>
    uri == 'dart:core' ||
    uri == 'dart:collection' ||
    uri.startsWith('package:content_models/');

/// The economy domain (specs/007-m05-local-economy, research R16): the
/// content domain, the trip engine's results, and its own folder.
bool _economyAllowed(String uri) =>
    _contentAllowed(uri) ||
    uri.startsWith('package:trip_engine/') ||
    uri.startsWith('package:wassal/core/content/domain/') ||
    uri.startsWith('package:wassal/core/economy/domain/') ||
    _sameFolder(uri);

/// The trip screen's domain (specs/008-m02-trip-screen/contracts/
/// trip-records.md "Guards"): the projection, the layout and the cues, over
/// the engine, the content domain and the glossary's identifiers (research
/// R23 converts between the two LineId enums).
bool _tripAllowed(String uri) =>
    _contentAllowed(uri) ||
    uri == 'dart:math' ||
    uri.startsWith('package:trip_engine/') ||
    uri == 'package:wassal/core/glossary/ids.dart' ||
    uri.startsWith('package:wassal/core/content/domain/') ||
    uri.startsWith('package:wassal/features/trip/domain/') ||
    _sameFolder(uri);

/// The account's and the sync's domains (specs/011-m06-identity-sync,
/// contracts/ci-checks.md "Domain imports"): JSON, the generated models, the
/// economy and content domains, and each other.
bool _syncAllowed(String uri) =>
    _contentAllowed(uri) ||
    uri == 'dart:convert' ||
    uri.startsWith('package:wassal/core/content/domain/') ||
    uri.startsWith('package:wassal/core/economy/domain/') ||
    uri.startsWith('package:wassal/core/account/domain/') ||
    uri.startsWith('package:wassal/core/sync/domain/') ||
    _sameFolder(uri);

/// The first session's domain (specs/012-m07-onboarding, contracts/
/// ci-checks.md "Guards"): grapheme clusters for the name rules, a seeded
/// `Random` for the suggested names, the engine and the trip's domain for
/// the coach, the economy and content domains for the first session's
/// facts, and M06's first-open outcome.
bool _onboardingAllowed(String uri) =>
    _contentAllowed(uri) ||
    uri == 'dart:math' ||
    uri == 'package:characters/characters.dart' ||
    uri == 'package:wassal/core/account/domain/account.dart' ||
    uri.startsWith('package:trip_engine/') ||
    uri.startsWith('package:wassal/core/content/domain/') ||
    uri.startsWith('package:wassal/core/economy/domain/') ||
    uri.startsWith('package:wassal/features/trip/domain/') ||
    uri.startsWith('package:wassal/features/onboarding/domain/') ||
    _sameFolder(uri);

/// The progression rules on the phone (specs/013-m08-home-result,
/// contracts/progress-rules.md): the generated models, the content source
/// they read them through and the SKU ids' wire names (each the models
/// only), and their own folder.
bool _progressAllowed(String uri) =>
    _contentAllowed(uri) ||
    uri == 'package:wassal/core/content/domain/content_source.dart' ||
    uri == 'package:wassal/core/economy/domain/wire.dart' ||
    uri.startsWith('package:wassal/core/progress/domain/') ||
    _sameFolder(uri);

/// Home's, the pre-trip card's and the result's domains
/// (specs/013-m08-home-result, contracts/seams.md "Repo guards touched"): the
/// engine, the content, economy and progress domains, the trip domain's
/// looks for the passengers' faces, and each other (the result shows Home's
/// savings target).
bool _screensAllowed(String uri) =>
    _contentAllowed(uri) ||
    uri.startsWith('package:trip_engine/') ||
    uri.startsWith('package:wassal/core/content/domain/') ||
    uri.startsWith('package:wassal/core/economy/domain/') ||
    uri.startsWith('package:wassal/core/progress/domain/') ||
    uri == 'package:wassal/features/trip/domain/looks.dart' ||
    uri.startsWith('package:wassal/features/home/domain/') ||
    uri.startsWith('package:wassal/features/pre_trip/domain/') ||
    uri.startsWith('package:wassal/features/result/domain/') ||
    _sameFolder(uri);

/// Lines' domain (specs/014-m09-lines-vehicles, research R18): the content
/// models and source, the SKU ids' wire names, the progression rules, and
/// Home's savings target and next trip, which it reuses rather than moves.
bool _linesAllowed(String uri) =>
    _contentAllowed(uri) ||
    uri == 'package:wassal/core/content/domain/content_source.dart' ||
    uri == 'package:wassal/core/economy/domain/wire.dart' ||
    uri.startsWith('package:wassal/core/progress/domain/') ||
    uri == 'package:wassal/features/home/domain/savings_target.dart' ||
    uri == 'package:wassal/features/home/domain/next_trip.dart' ||
    uri.startsWith('package:wassal/features/lines/domain/') ||
    _sameFolder(uri);

/// The apartment's and the story's domains (specs/015-m10-apartment-story,
/// research R20): the content models and source, the SKU ids' wire names, the
/// progress rules, Home's savings target (the goal card reuses M08's) and
/// their own folder. The trip's `rider_comments.dart` stays under
/// `_tripAllowed`.
bool _storyAllowed(String uri) =>
    _contentAllowed(uri) ||
    uri == 'package:wassal/core/content/domain/content_source.dart' ||
    uri.startsWith('package:wassal/core/content/domain/') ||
    uri == 'package:wassal/core/economy/domain/wire.dart' ||
    uri.startsWith('package:wassal/core/progress/domain/') ||
    uri == 'package:wassal/features/home/domain/savings_target.dart' ||
    _sameFolder(uri);

/// Files allowed one more import than their folder: the economy checks a
/// name with the onboarding's rules, the one check the phone and the economy
/// share (M07 research R7, R8). Nothing else of `features/`.
const _fileExceptions = <String, Set<String>>{
  'lib/core/economy/domain/profile_rules.dart': {
    'package:wassal/features/onboarding/domain/name_rules.dart',
  },
};

/// A file of the same folder, by relative path.
bool _sameFolder(String uri) =>
    !uri.contains(':') && !uri.contains('/') && !uri.contains('..');

const _domains = <String, bool Function(String)>{
  'lib/core/content/domain': _contentAllowed,
  'lib/core/economy/domain': _economyAllowed,
  'lib/features/trip/domain': _tripAllowed,
  'lib/core/account/domain': _syncAllowed,
  'lib/core/sync/domain': _syncAllowed,
  'lib/features/onboarding/domain': _onboardingAllowed,
  'lib/core/progress/domain': _progressAllowed,
  'lib/features/home/domain': _screensAllowed,
  'lib/features/pre_trip/domain': _screensAllowed,
  'lib/features/result/domain': _screensAllowed,
  'lib/features/lines/domain': _linesAllowed,
  // M10's `lib/features/apartment/domain` and `lib/features/story/domain`
  // join here with their first files (specs/015-m10-apartment-story, T030).
};

final _directive = RegExp(
  r'''^[ \t]*(?:import|export)\s+['"]([^'"]+)['"]''',
  multiLine: true,
);

List<String> forbiddenImports(
  String source, [
  bool Function(String uri) allowed = _contentAllowed,
]) {
  final stripped = stripComments(source);
  return [
    for (final match in _directive.allMatches(stripped))
      if (!allowed(match[1]!))
        '${'\n'.allMatches(stripped.substring(0, match.start)).length + 1}: '
            '${match[1]}',
  ];
}

void main() {
  for (final MapEntry(key: folder, value: allowed) in _domains.entries) {
    test('$folder imports only what it allows', () {
      final dir = Directory(folder);
      expect(dir.existsSync(), isTrue, reason: '$folder must exist');
      final files = dir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();
      expect(files, isNotEmpty);
      final violations = [
        for (final file in files)
          for (final hit in forbiddenImports(
            file.readAsStringSync(),
            (uri) =>
                allowed(uri) ||
                (_fileExceptions[file.path.replaceAll(r'\', '/')]?.contains(
                      uri,
                    ) ??
                    false),
          ))
            '${file.path}:$hit',
      ];
      expect(violations, isEmpty, reason: violations.join('\n'));
    });
  }

  test('every domain folder under lib/ has its list', () {
    final folders = {
      for (final dir in Directory('lib').listSync(recursive: true))
        if (dir is Directory &&
            dir.path.endsWith('${Platform.pathSeparator}domain'))
          dir.path.replaceAll(r'\', '/'),
    };
    expect(folders, _domains.keys.toSet());
  });

  test('the content scan catches forbidden imports and ignores the rest', () {
    expect(forbiddenImports("import 'package:flutter/foundation.dart';"), [
      '1: package:flutter/foundation.dart',
    ]);
    expect(forbiddenImports("library;\n\nimport 'dart:io';"), ['3: dart:io']);
    expect(forbiddenImports("export 'package:dio/dio.dart';"), hasLength(1));
    expect(
      forbiddenImports("import 'package:wassal/core/x.dart';"),
      hasLength(1),
    );
    expect(
      forbiddenImports("import 'package:trip_engine/trip_engine.dart';"),
      hasLength(1),
    );
    expect(
      forbiddenImports(
        "import 'package:content_models/content_models.dart';\n"
        "import 'dart:collection';\n"
        "import 'dart:core';",
      ),
      isEmpty,
    );
    expect(forbiddenImports("// import 'dart:io';"), isEmpty);
  });

  test('the story scan allows its list and refuses the rest', () {
    List<String> scan(String uri) =>
        forbiddenImports("import '$uri';", _storyAllowed);
    for (final ok in [
      'chapter_rows.dart',
      'package:wassal/core/progress/domain/story.dart',
      'package:wassal/core/economy/domain/wire.dart',
      'package:wassal/core/content/domain/content_source.dart',
      'package:wassal/features/home/domain/savings_target.dart',
      'package:content_models/content_models.dart',
    ]) {
      expect(scan(ok), isEmpty, reason: ok);
    }
    for (final bad in [
      '../presentation/rooms_view.dart',
      'package:wassal/core/economy/economy.dart',
      'package:wassal/features/home/domain/home_model.dart',
      'package:wassal/features/trip/domain/rider_comments.dart',
      'package:flutter/foundation.dart',
      'dart:io',
    ]) {
      expect(scan(bad), hasLength(1), reason: bad);
    }
  });

  test('the economy scan allows its list and refuses the rest', () {
    List<String> scan(String uri) =>
        forbiddenImports("import '$uri';", _economyAllowed);
    for (final ok in [
      'fuel.dart',
      'package:wassal/core/economy/domain/fuel.dart',
      'package:wassal/core/content/domain/content_source.dart',
      'package:trip_engine/trip_engine.dart',
      'package:content_models/content_models.dart',
      'dart:collection',
    ]) {
      expect(scan(ok), isEmpty, reason: ok);
    }
    for (final bad in [
      '../economy.dart',
      'sub/fuel.dart',
      'package:wassal/core/economy/economy.dart',
      'package:wassal/core/storage/app_database.dart',
      'package:uuid/uuid.dart',
      'package:drift/drift.dart',
      'package:flutter/foundation.dart',
      'dart:io',
      'dart:math',
    ]) {
      expect(scan(bad), hasLength(1), reason: bad);
    }
  });

  test('the account and sync scan allows its list and refuses the rest', () {
    List<String> scan(String uri) =>
        forbiddenImports("import '$uri';", _syncAllowed);
    for (final ok in [
      'pass.dart',
      'dart:convert',
      'dart:collection',
      'package:content_models/content_models.dart',
      'package:wassal/core/economy/domain/economy_state.dart',
      'package:wassal/core/content/domain/content_source.dart',
      'package:wassal/core/account/domain/account.dart',
      'package:wassal/core/sync/domain/wire/reader.dart',
    ]) {
      expect(scan(ok), isEmpty, reason: ok);
    }
    for (final bad in [
      'package:flutter/foundation.dart',
      'package:dio/dio.dart',
      'package:drift/drift.dart',
      'package:uuid/uuid.dart',
      'package:wassal/core/network/api_client.dart',
      'package:wassal/core/economy/economy.dart',
      'package:trip_engine/trip_engine.dart',
      'dart:io',
      'dart:async',
    ]) {
      expect(scan(bad), hasLength(1), reason: bad);
    }
  });

  test('the onboarding scan allows its list and refuses the rest', () {
    List<String> scan(String uri) =>
        forbiddenImports("import '$uri';", _onboardingAllowed);
    for (final ok in [
      'name_rules.dart',
      'package:characters/characters.dart',
      'package:trip_engine/trip_engine.dart',
      'package:content_models/content_models.dart',
      'package:wassal/core/content/domain/content_source.dart',
      'package:wassal/core/economy/domain/economy_state.dart',
      'package:wassal/features/trip/domain/trip_view.dart',
      'package:wassal/features/onboarding/domain/name_rules.dart',
      'package:wassal/core/account/domain/account.dart',
    ]) {
      expect(scan(ok), isEmpty, reason: ok);
    }
    for (final bad in [
      'package:flutter/widgets.dart',
      'package:drift/drift.dart',
      'package:wassal/features/trip/application/trip_controller.dart',
      'package:wassal/features/onboarding/data/drift_first_session_store.dart',
      'package:wassal/core/economy/economy.dart',
      'dart:io',
    ]) {
      expect(scan(bad), hasLength(1), reason: bad);
    }
  });

  test('only profile_rules.dart may import a features/ file, and one only', () {
    expect(_fileExceptions.keys, [
      'lib/core/economy/domain/profile_rules.dart',
    ]);
    expect(_fileExceptions.values.single, {
      'package:wassal/features/onboarding/domain/name_rules.dart',
    });
  });

  test('the progress scan allows its list and refuses the rest', () {
    List<String> scan(String uri) =>
        forbiddenImports("import '$uri';", _progressAllowed);
    for (final ok in [
      'unlocks.dart',
      'package:content_models/content_models.dart',
      'package:wassal/core/content/domain/content_source.dart',
      'package:wassal/core/economy/domain/wire.dart',
      'dart:collection',
    ]) {
      expect(scan(ok), isEmpty, reason: ok);
    }
    for (final bad in [
      'package:flutter/foundation.dart',
      'package:trip_engine/trip_engine.dart',
      'package:wassal/core/economy/economy.dart',
      'package:wassal/core/economy/domain/economy_state.dart',
      'dart:io',
    ]) {
      expect(scan(bad), hasLength(1), reason: bad);
    }
  });

  test('the screens scan allows its list and refuses the rest', () {
    List<String> scan(String uri) =>
        forbiddenImports("import '$uri';", _screensAllowed);
    for (final ok in [
      'briefing.dart',
      'package:content_models/content_models.dart',
      'package:trip_engine/trip_engine.dart',
      'package:wassal/core/content/domain/content_source.dart',
      'package:wassal/core/economy/domain/economy_state.dart',
      'package:wassal/core/progress/domain/unlocks.dart',
      'package:wassal/features/trip/domain/looks.dart',
    ]) {
      expect(scan(ok), isEmpty, reason: ok);
    }
    for (final bad in [
      'package:flutter/widgets.dart',
      'package:wassal/core/economy/economy.dart',
      'package:wassal/features/trip/domain/trip_view.dart',
      'package:wassal/features/onboarding/domain/first_session.dart',
      'package:wassal/features/home/application/home_model.dart',
      'dart:io',
      'dart:ui',
    ]) {
      expect(scan(bad), hasLength(1), reason: bad);
    }
  });

  test('the trip scan allows its list and refuses the rest', () {
    List<String> scan(String uri) =>
        forbiddenImports("import '$uri';", _tripAllowed);
    for (final ok in [
      'trip_view.dart',
      'package:wassal/features/trip/domain/trip_view.dart',
      'package:wassal/core/content/domain/content_source.dart',
      'package:trip_engine/trip_engine.dart',
      'package:content_models/content_models.dart',
      'package:wassal/core/glossary/ids.dart',
      'dart:collection',
      'dart:math',
    ]) {
      expect(scan(ok), isEmpty, reason: ok);
    }
    for (final bad in [
      'package:flutter/widgets.dart',
      'package:flame/game.dart',
      'package:drift/drift.dart',
      'package:wassal/features/trip/application/trip_controller.dart',
      'package:wassal/core/l10n/number_formatter.dart',
      '../application/trip_controller.dart',
      'dart:ui',
      'dart:io',
    ]) {
      expect(scan(bad), hasLength(1), reason: bad);
    }
  });
}
