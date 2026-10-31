// A story trip's rider changes nothing the engine does (specs/015-m10-
// apartment-story T129, contracts/story-trip.md "Comments", constitution I):
// M02's scripted player plays a trip whose chapter seats المعلم in `A_l`,
// and the test counts what he says. One short change makes him comment once;
// an over-change makes no comment; and each run's `TripResult` is the one the
// same trip gives with nobody riding. Headless:
//
//   fvm flutter test integration_test/story_trip_test.dart -d flutter-tester
//
// or on a device with `--flavor dev`.
import 'dart:convert';

import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wassal/core/content/pack_content_source.dart';
import 'package:wassal/features/trip/application/trip_controller.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';

import '../test/helpers/content.dart';
import '../test/helpers/economy.dart';
import '../test/helpers/trip.dart';

/// A rider comments after a short change, and after nothing else here.
const _shortChange = 'core__short_then_topup';
const _overChange = 'core__over_change_kept';

/// The sample pack with chapter 1's story trip moved to [tripId], and its
/// rider (المعلم, in `A_l`) kept or taken out.
Map<String, Object?> _pack(String tripId, {required bool rider}) {
  final json = jsonDecode(jsonEncode(samplePackJson())) as Map<String, Object?>;
  final chapter = (json['chapters']! as List<Object?>)
      .cast<Map<String, Object?>>()
      .firstWhere((c) => c['chapter_id'] == 'ch1_first_job');
  chapter['story_trip_id'] = tripId;
  if (!rider) {
    (chapter['story_trip_info']! as Map<String, Object?>)['riders'] =
        <Object?>[];
  }
  return json;
}

/// What a run said and ended with.
typedef _Run = ({List<String> comments, Map<String, Object?> result});

/// Plays [name] through the screen's controls with [rider] on board or not.
Future<_Run> _play(
  WidgetTester tester,
  String name, {
  required bool rider,
}) async {
  final fixture = loadFixture(name);
  final json = _pack(fixture.definition.tripId, rider: rider);
  final economy = await testEconomy(
    content: PackContentSource(Pack.fromJson(json)),
  );
  await pumpTrip(
    tester,
    tripId: fixture.definition.tripId,
    economy: economy,
    content: contentTestOverrides(
      assets: bundledAssetsFor(encodePackFile(json)),
    ),
    fixed: FixedTrip(
      definition: fixture.definition,
      params: fixture.params,
      seed: fixture.seed,
    ),
  );
  // Each comment as it shows: a rider bubble that differs from the last.
  final comments = <String>[];
  RiderBubbleView? last;
  final run = await ScriptedPlayer(
    tester,
    fixture,
    onFrame: () async {
      final now = controllerOf(tester).view?.riderBubble;
      if (now != null && now != last) comments.add(now.text);
      last = now;
    },
  ).drive();
  expect(run.inexact, isFalse);
  expect(run.result, isNotNull, reason: '${run.exit}');
  return (comments: comments, result: run.result!.toJson());
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a short change makes the rider comment once', (tester) async {
    final run = await _play(tester, _shortChange, rider: true);
    expect(run.comments, hasLength(1));
    expect(run.comments.single, isNotEmpty);
    expect(run.result, loadFixture(_shortChange).expectedResult.toJson());
  });

  testWidgets('an over-change makes none', (tester) async {
    final run = await _play(tester, _overChange, rider: true);
    expect(run.comments, isEmpty);
    expect(run.result, loadFixture(_overChange).expectedResult.toJson());
  });

  // The same two trips with nobody riding end with the fixtures' results too
  // (the ones the rider's runs above equal), and say nothing.
  for (final name in [_shortChange, _overChange]) {
    testWidgets('$name without a rider: the same result', (tester) async {
      final run = await _play(tester, name, rider: false);
      expect(run.comments, isEmpty);
      expect(run.result, loadFixture(name).expectedResult.toJson());
    });
  }
}
