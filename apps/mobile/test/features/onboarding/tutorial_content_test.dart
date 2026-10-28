import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/content/bundled_pack.dart';
import 'package:wassal/core/content/decode_pack_file.dart';
import 'package:wassal/core/content/domain/content_source.dart';
import 'package:wassal/features/onboarding/domain/first_session.dart';
import 'package:wassal/features/onboarding/domain/tutorial_coach.dart';

import '../../helpers/coached_player.dart';
import '../../helpers/economy.dart';
import '../../helpers/trip.dart';
import '../../helpers/tutorial_content.dart';

// The tutorial is playable as taught (FR-047): a player who does only what
// بلية points at sees each lesson's step and earns at least a star on each
// tutorial trip, on the fixture and on the release pack when one is bundled.
// Trip 5 has no step; there the player does what lesson 1 taught.

const _release = 'assets/content/release';

/// The bundled release pack, or null while none is committed.
ContentSource? _releaseContent() {
  final record = File('$_release/bundled.json');
  if (!record.existsSync()) return null;
  final parsed = BundledPackRecord.parse(record.readAsBytesSync());
  final bytes = File('$_release/${parsed.file}').readAsBytesSync();
  return switch (decodePackFile(bytes, parsed.expected)) {
    PackDecoded(:final source) => source,
    PackRefused(:final reason) => throw StateError('refused: $reason'),
  };
}

/// Each tutorial trip of [content], coached by its lesson.
void _coachesEveryTrip(ContentSource Function() content) {
  for (var lesson = 0; lesson < tutorialTripCount; lesson++) {
    test('trip ${lesson + 1}: its step, then at least one star', () async {
      final source = content();
      final tripId = tutorialTripsOf(source)[lesson];
      final economy = await testEconomy(content: source);
      final c = testController(economy, coachLesson: () => lesson);
      await c.open(tripId);
      // Trip 5 has no step: its player plays as lesson 1 taught.
      final ownStep = lesson >= CoachStepId.values.length;
      final run = await playCoached(c, onItsOwn: ownStep);
      expect(run.steps, [
        if (lesson < CoachStepId.values.length) CoachStepId.values[lesson],
      ]);
      expect(run.result.stars, greaterThanOrEqualTo(1), reason: tripId);
    });
  }
}

void main() {
  group('the fixture', () {
    test('has the five tutorial trips', () {
      expect(tutorialTripsOf(tutorialContent()), tutorialTripIds);
    });
    _coachesEveryTrip(tutorialContent);
  });

  group(
    'the release pack',
    () => _coachesEveryTrip(() => _releaseContent()!),
    skip: File('$_release/bundled.json').existsSync()
        ? false
        : 'no release pack bundled yet (content-publishing.md §3)',
  );
}
