// What the US6 fixtures pin: the aids, the endings and the story sample
// (rules.md §4.4, §4.9, §4.11 to §4.13, §10, §11).
import 'package:content_models/content_models.dart';
import 'package:test/test.dart';
import 'package:trip_engine/trip_engine.dart';

import '../../support/fixture_io.dart';
import '../../support/scripts.dart';

final us6Expectations = <String, Expectation>{
  'command__request_break.json': (run) {
    // §4.9: two breaks of 1000, each back as 500, 100×4 and 50×2 after
    // 1.5 s; the third request was rejected and isn't logged.
    final log = run.engine.commandLog;
    expect(log.where((e) => e.command is RequestBreak), hasLength(2));
    final done = eventsOf<BreakCompleted>(run.events);
    expect(done, hasLength(2));
    for (final completed in done) {
      expect(completed.pieces.toJson(), {'50': 2, '100': 4, '500': 1});
    }
    expect(done.first.tMs, 1518);
    expect(run.engine.state.breaksUsed, 2);
    expect(resultOf(run).stars, 3);
  },
  'command__undo_last_send.json': (run) {
    // §4.4: the wrong 500 is undone before it leaves, then 300 is sent.
    final undone = eventsOf<SendUndone>(run.events).single;
    expect(eventsOf<ChangeSent>(run.events).map((e) => e.amountPiasters), [
      500,
      300,
    ]);
    expect(undone.tokenId, eventsOf<ChangeSent>(run.events).first.tokenId);
    expect(resultOf(run).mistakes, isEmpty);
  },
  'booster__change_bag.json': (run) {
    // §4.11: with only a 1000 in the tray, the change bag makes the change.
    expect(
      eventsOf<BoosterUsed>(run.events).single.boosterId,
      BoosterId.changeBag,
    );
    expect(resultOf(run).boostersUsed, [BoosterId.changeBag]);
    expect(resultOf(run).stars, 3);
  },
  'booster__wake_all.json': (run) {
    // §4.11: both sleepers wake at once, twice.
    final woke = eventsOf<PassengerWoke>(run.events);
    expect(woke.map((e) => e.tMs).toSet(), hasLength(2));
    expect(woke, hasLength(4));
    expect(eventsOf<PassengerWaking>(run.events), isEmpty);
    expect(resultOf(run).boostersUsed, [BoosterId.wakeAll, BoosterId.wakeAll]);
  },
  'booster__ledger_peek.json': (run) {
    // §3 step 2.4: the peek lasts booster_ledger_peek_ms.
    final started = eventsOf<LedgerPeekStarted>(run.events).single;
    expect(
      started.untilMs - started.tMs,
      run.engine.params.boosterLedgerPeekMs,
    );
    final ended = eventsOf<LedgerPeekEnded>(run.events).single.tMs;
    expect(ended, inInclusiveRange(started.untilMs, started.untilMs + 32));
  },
  'booster__traffic_jam.json': (run) {
    // §4.11: three jams of 10 s each; the fourth was booster_limit.
    expect(eventsOf<ScheduleShifted>(run.events).map((e) => e.deltaMs), [
      10000,
      10000,
      10000,
    ]);
    expect(eventsOf<StationReached>(run.events).single.tMs, 50028);
    expect(resultOf(run).boostersUsed, hasLength(3));
  },
  'ending__failed.json': (run) {
    // §10.2: four fights take reputation below 0; the trip fails there,
    // revivable, with 0 stars and no earnings.
    final result = resultOf(run);
    expect(result.outcome, TripOutcome.failed);
    expect(
      (result.stars, result.earningsJenehat, result.reputation),
      (0, 0, 0),
    );
    expect(result.reputationLost, {RepCause.fight: 120});
    expect(run.engine.state.revivable, isTrue);
  },
  'ending__revived.json': (run) {
    // §4.12: revived at rep_revive_to, the trip finishes with revived set.
    final revive = eventsOf<TripRevived>(run.events).single;
    expect(revive.reputation, run.engine.params.repReviveTo);
    final result = resultOf(run);
    expect((result.outcome, result.revived), (TripOutcome.finished, true));
    expect(result.stars, 1);
  },
  'ending__abandoned.json': (run) {
    // §4.13: abandoned mid-trip: 0 stars and no earnings.
    final result = resultOf(run);
    expect(result.outcome, TripOutcome.abandoned);
    expect((result.stars, result.earningsJenehat), (0, 0));
    expect(result.durationMs, run.engine.commandLog.last.tMs);
  },
  'ending__story_fight_fails.json': (run) {
    // §10.2: in a no-fights story trip the first fight fails it for good.
    expect(run.engine.definition.kind, TripKind.story);
    final failed = eventsOf<TripFailed>(run.events).single;
    expect(failed.revivable, isFalse);
    expect(resultOf(run).fights, 1);
    expect(resultOf(run).reputation, 70);
  },
  'sample__line_hay_03_three_stars.json': (run) {
    // The story sample to 3 stars, with no fights.
    expect(run.engine.definition.tripId, 'line_hay.03');
    expect(run.engine.definition.rules.noFightsRequired, isTrue);
    expect(resultOf(run).stars, 3);
  },
};

final stressExpectations = <String, Expectation>{
  'stress__longest_trip.json': (run) {
    // SC-004, SC-005: a full micro_old with 30 passengers, 10 traffic events
    // and 5 traffic jams, so the last station comes at 1,500 s; 1,200
    // accepted commands.
    final definition = run.engine.definition;
    expect(definition.passengers, hasLength(30));
    expect(definition.events, hasLength(10));
    expect(run.engine.commandLog, hasLength(1200));
    expect(eventsOf<PassengerBoarded>(run.events), hasLength(20));
    expect(
      eventsOf<StationReached>(run.events).last.tMs,
      greaterThanOrEqualTo(1500000),
    );
    expect(resultOf(run).stars, 3);
  },
};
