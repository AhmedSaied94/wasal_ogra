import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/core/l10n/number_formatter.dart';
import 'package:wassal/features/trip/domain/fail_summary.dart';
import 'package:wassal/features/trip/domain/trip_facts.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';
import 'package:wassal/features/trip/presentation/trip_text.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

import '../../../helpers/trip.dart';

// The failure card's causes and its revive offer (tasks.md T081,
// contracts/trip-view.md "Failure summary", contracts/trip-controller.md
// "Revive").

/// [fixture]'s engine with its log played and the trip run out.
TripEngine replayed(ParityFixture fixture) {
  final engine = TripEngine.start(
    fixture.definition,
    fixture.params,
    seed: fixture.seed,
  );
  for (final entry in fixture.commandLog) {
    while (engine.state.tMs < entry.tMs &&
        engine.status == TripStatus.running) {
      engine.step();
    }
    engine.apply(entry.command);
  }
  while (engine.status == TripStatus.running) {
    engine.step();
  }
  return engine;
}

/// The top two losses of [lost] by points, the earlier cause on a tie.
List<RepCause> topTwo(Map<RepCause, int> lost) {
  final left = {
    for (final MapEntry(key: cause, value: points) in lost.entries)
      if (cause.loss && points > 0) cause: points,
  };
  final top = <RepCause>[];
  while (top.length < 2 && left.isNotEmpty) {
    RepCause? best;
    for (final cause in RepCause.values) {
      final points = left[cause];
      if (points == null) continue;
      if (best == null || points > left[best]!) best = cause;
    }
    top.add(best!);
    left.remove(best);
  }
  return top;
}

TripFacts factsOf(ParityFixture fixture) =>
    factsFor(fixture.definition, params: fixture.params, withLine: false);

void main() {
  group('causes', () {
    test('every fixture: the top two by points, each counted', () {
      var failed = 0;
      for (final name in allFixtureNames()) {
        final fixture = loadFixture(name);
        final state = replayed(fixture).state;
        final facts = factsOf(fixture);
        final summary = failSummary(state.reputationLost, facts, null);
        expect(
          [for (final c in summary.causes) c.cause],
          topTwo(state.reputationLost),
          reason: name,
        );
        for (final c in summary.causes) {
          expect(
            c.count! * facts.penaltyOf(c.cause)!,
            state.reputationLost[c.cause],
            reason: '$name ${c.cause}',
          );
        }
        if (state.status == TripStatus.failed) {
          failed++;
          expect(summary.causes, isNotEmpty, reason: name);
        }
      }
      expect(failed, greaterThan(0));
    });

    test('of three, the two that cost most; a tie keeps the earlier', () {
      final facts = factsOf(loadFixture('ending__failed'));
      final p = facts.params;
      final summary = failSummary(
        {
          RepCause.shortChange: 3 * p.repShortChange,
          RepCause.fight: 2 * p.repFight,
          RepCause.missedStop: p.repMissedStop,
          RepCause.exactChange: 99,
        },
        facts,
        null,
      );
      expect(summary.causes, [
        const FailCause(cause: RepCause.fight, count: 2),
        const FailCause(cause: RepCause.missedStop, count: 1),
      ]);

      final tie = failSummary(
        {RepCause.impatient: 10, RepCause.shortChange: 10},
        facts,
        null,
      );
      expect(
        [for (final c in tie.causes) c.cause],
        [RepCause.shortChange, RepCause.impatient],
      );
    });
  });

  group('words', () {
    final l10n = lookupAppLocalizations(const Locale('ar'));
    const numbers = NumberFormatter(DigitStyle.arabicIndic);
    String line(Map<RepCause, int> counts) => l10n.failCauses(
      FailSummary(
        causes: [
          for (final MapEntry(key: cause, value: count) in counts.entries)
            FailCause(cause: cause, count: count),
        ],
        revive: null,
      ),
      numbers,
    );

    test('«خناقتين وراكب فاتته محطته»', () {
      expect(
        line({RepCause.fight: 2, RepCause.missedStop: 1}),
        'خناقتين وراكب فاتته محطته',
      );
      expect(line({RepCause.fight: 1}), 'خناقة');
      expect(line({}), isEmpty);
    });

    test('a plural form per count, in the player\'s digits', () {
      expect(line({RepCause.fight: 3}), '${numbers.integer(3)} خناقات');
      expect(line({RepCause.fight: 11}), '${numbers.integer(11)} خناقة');
      final western = l10n.failCause(
        const FailCause(cause: RepCause.fight, count: 4),
        const NumberFormatter(DigitStyle.western),
      );
      expect(western, contains('4'));
      for (final cause in RepCause.values.where((c) => c.loss)) {
        final forms = {
          for (final count in [1, 2, 3, 11])
            l10n.failCause(FailCause(cause: cause, count: count), numbers),
        };
        expect(forms, hasLength(4), reason: '$cause');
        expect(forms.every((f) => f.isNotEmpty), isTrue, reason: '$cause');
      }
    });
  });

  group('revive', () {
    final fixture = loadFixture('ending__failed');
    final failed = replayed(fixture).state;

    test('offered when revivable, below the cap, unpaid and priced', () {
      expect(failed.status, TripStatus.failed);
      expect(
        reviveOffer(failed, priceBonat: 20, bonat: 20, paid: false),
        const ReviveOffer(priceBonat: 20, affordable: true),
      );
      expect(
        reviveOffer(failed, priceBonat: 20, bonat: 19, paid: false),
        const ReviveOffer(priceBonat: 20, affordable: false),
      );
      expect(
        reviveOffer(failed, priceBonat: 20, bonat: 99, paid: true),
        isNull,
      );
      expect(
        reviveOffer(failed, priceBonat: null, bonat: 99, paid: false),
        isNull,
      );
    });

    test('never once revived, or after a story fight', () {
      final revived = replayed(loadFixture('ending__revived')).state;
      expect(revived.revived, isTrue);
      expect(
        reviveOffer(revived, priceBonat: 20, bonat: 99, paid: false),
        isNull,
      );
      final story = replayed(loadFixture('ending__story_fight_fails')).state;
      expect(story.status, TripStatus.failed);
      expect(
        reviveOffer(story, priceBonat: 20, bonat: 99, paid: false),
        isNull,
      );
    });

    test('never at the command cap', () {
      TripState failingAfter(int commands) {
        final engine = TripEngine.start(
          fixture.definition,
          fixture.params,
          seed: fixture.seed,
        );
        final note = engine.state.tray.counts.keys.first;
        while (engine.state.commandsAccepted < commands) {
          engine.apply(
            engine.state.hand.isEmpty ? PickFromTray(note) : const ReturnHand(),
          );
        }
        while (engine.status == TripStatus.running) {
          engine.step();
        }
        expect(engine.status, TripStatus.failed);
        return engine.state;
      }

      expect(
        reviveOffer(
          failingAfter(reviveCommandCap - 1),
          priceBonat: 20,
          bonat: 99,
          paid: false,
        ),
        isNotNull,
      );
      final capped = failingAfter(reviveCommandCap);
      expect(
        reviveOffer(capped, priceBonat: 20, bonat: 99, paid: false),
        isNull,
      );
      // What the cap spares the player: the engine would refuse it.
      expect(capped.revivable, isTrue);
    });
  });
}
