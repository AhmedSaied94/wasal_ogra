// The TripEngine shell: starting, the clock, pausing, the log, the cap, the
// status table and the failure check (rules.md §2–§4, §10.2).
import 'package:content_models/content_models.dart';
import 'package:test/test.dart';
import 'package:trip_engine/src/engine.dart';
import 'package:trip_engine/src/rules/command_handlers.dart'
    show allowedStatuses, commandCap;
import 'package:trip_engine/trip_engine.dart';

import '../support/builders.dart';
import '../support/default_params.dart';
import '../support/scripts.dart';

final _definition =
    (TripBuilder()
          ..station('kobri', 30)
          ..passenger(
            'p1',
            seat: 'A_r',
            dest: 'kobri',
            payment: [500, 100, 100],
          )
          ..tray({100: 4, 50: 4}))
        .build();

void main() {
  group('starting', () {
    test('an invalid trip throws TripRefused', () {
      expect(
        () => startTrip(_definition, seed: 0),
        throwsA(isA<TripRefused>()),
      );
    });

    test(
      'a valid trip starts running at 0 with reputation 100 and its tray',
      () {
        final engine = startTrip(_definition);
        expect(engine.status, TripStatus.running);
        expect(engine.state.tMs, 0);
        expect(engine.state.reputation, 100);
        expect(engine.state.tray, Pieces({100: 4, 50: 4}));
        expect(engine.state.hand.isEmpty, isTrue);
        expect(engine.state.prng, 1);
        expect(engine.result, isNull);
        expect(engine.commandLog, isEmpty);
      },
    );

    test('the seed defaults to the definition and can be overridden', () {
      expect(startTrip(_definition).state.prng, _definition.seed);
      expect(startTrip(_definition, seed: 99).state.prng, 99);
    });
  });

  group('the clock', () {
    test('step() advances 33 ms', () {
      final engine = startTrip(_definition);
      engine.step();
      expect(engine.state.tMs, 33);
      engine.step();
      expect(engine.state.tMs, 66);
    });

    test('stepTo(330) takes 10 steps, and stepTo never goes back', () {
      final engine = startTrip(_definition);
      engine.stepTo(330);
      expect(engine.state.tMs, 330);
      engine.stepTo(100);
      expect(engine.state.tMs, 330);
      engine.stepTo(340);
      expect(engine.state.tMs, 363);
    });

    test('the input state is never changed', () {
      final engine = startTrip(_definition);
      final before = engine.state;
      final json = before.toJson();
      engine
        ..step()
        ..ok(const PickFromTray(100));
      expect(before.toJson(), json);
      expect(identical(before, engine.state), isFalse);
    });
  });

  group('pausing', () {
    test('pause() stops the clock and resume() continues', () {
      final engine = startTrip(_definition)..step();
      engine.pause();
      expect(engine.status, TripStatus.paused);
      expect(engine.step(), isEmpty);
      expect(engine.stepTo(5000), isEmpty);
      expect(engine.state.tMs, 33);
      engine.resume();
      expect(engine.status, TripStatus.running);
      engine.step();
      expect(engine.state.tMs, 66);
    });

    test('pause and resume are never logged and are no-ops otherwise', () {
      final engine = startTrip(_definition)
        ..pause()
        ..pause()
        ..resume()
        ..resume();
      expect(engine.status, TripStatus.running);
      expect(engine.commandLog, isEmpty);
      expect(engine.state.commandsAccepted, 0);
    });
  });

  group('the log', () {
    test('an accepted command is logged at the current t_ms', () {
      final engine = startTrip(_definition)..stepTo(330);
      engine.ok(const PickFromTray(100));
      expect(engine.commandLog.single.toJson(), [330, 'PickFromTray', 100]);
      expect(engine.state.commandsAccepted, 1);
      expect(() => engine.commandLog.clear(), throwsUnsupportedError);
    });

    test('a rejected command is not logged', () {
      final engine = startTrip(_definition);
      engine.rejects(const PickFromTray(1000), RejectionCode.trayEmpty);
      engine.rejects(const ReturnHand(), RejectionCode.handEmpty);
      expect(engine.commandLog, isEmpty);
      expect(engine.state.commandsAccepted, 0);
    });

    test('the 1,201st command is rejected with command_limit', () {
      final engine = startTrip(_definition);
      for (var i = 0; i < 600; i++) {
        engine
          ..ok(const PickFromTray(100))
          ..ok(const ReturnHand());
      }
      expect(engine.commandLog, hasLength(1200));
      engine.rejects(const PickFromTray(100), RejectionCode.commandLimit);
      engine.step();
      expect(engine.state.tMs, 33, reason: 'the trip still runs');
    });

    test('Abandon is still accepted at the cap, and replays', () {
      final engine = startTrip(_definition);
      for (var i = 0; i < 600; i++) {
        engine
          ..ok(const PickFromTray(100))
          ..ok(const ReturnHand());
      }
      engine.ok(const Abandon());
      expect(engine.status, TripStatus.abandoned);
      expect(engine.commandLog, hasLength(1201));
      expect(engine.state.commandsAccepted, 1201);
      expect(
        replay(
          _definition,
          engine.replayRecord.params,
          engine.seed,
          engine.commandLog,
        ).toJson(),
        engine.result?.toJson(),
      );
    });

    test('a failed trip at the cap can be abandoned, not revived', () {
      final engine = startTrip(_definition)
        ..debugEdit((tx) {
          tx
            ..commandsAccepted = commandCap
            ..status = TripStatus.failed;
        });
      engine.rejects(const Revive(), RejectionCode.commandLimit);
      engine.ok(const Abandon());
      expect(engine.status, TripStatus.abandoned);
    });
  });

  group('status checks', () {
    test('the data-model.md "Commands" table', () {
      const running = {TripStatus.running};
      const choices = {TripStatus.running, TripStatus.paused};
      final table = <Command, Set<TripStatus>>{
        const PickFromTray(100): running,
        const ReturnHand(): running,
        const SendHand('p1'): running,
        const UndoLastSend(): running,
        const Tap('p1'): running,
        const ResolveClaim('p1', insist: true): choices,
        const ResolveDispute(0, 'p1'): choices,
        const ResolveChangeRequest('p1', agree: true): choices,
        const RequestBreak(1000): running,
        const CollectDropped(1): running,
        const UseBooster(BoosterId.changeBag): choices,
        const Revive(): {TripStatus.failed},
        const Abandon(): {
          TripStatus.running,
          TripStatus.paused,
          TripStatus.failed,
        },
      };
      for (final MapEntry(key: command, value: statuses) in table.entries) {
        expect(allowedStatuses(command), statuses, reason: command.name);
      }
    });

    test('a command outside its statuses is rejected with wrong_status', () {
      final paused = startTrip(_definition)..pause();
      paused.rejects(const PickFromTray(100), RejectionCode.wrongStatus);
      paused.rejects(const Tap('p1'), RejectionCode.wrongStatus);
      paused.rejects(const Revive(), RejectionCode.wrongStatus);
      final running = startTrip(_definition);
      running.rejects(const Revive(), RejectionCode.wrongStatus);
      for (final status in [TripStatus.finished, TripStatus.abandoned]) {
        final ended = startTrip(_definition)
          ..debugEdit((tx) => tx.status = status);
        ended.rejects(const Abandon(), RejectionCode.wrongStatus);
        ended.rejects(
          const UseBooster(BoosterId.changeBag),
          RejectionCode.wrongStatus,
        );
        expect(ended.step(), isEmpty);
      }
    });
  });

  group('failure (§10.2)', () {
    test('reputation driven to 0 fails the trip at the next check', () {
      final engine = startTrip(_definition)..stepTo(330);
      engine.debugEdit((tx) => tx.reputation = 0);
      final events = engine.step();
      expect(engine.status, TripStatus.failed);
      expect(engine.state.tMs, 363);
      final failed = eventsOf<TripFailed>(events).single;
      expect(failed.revivable, isTrue);
      expect(engine.result!.outcome, TripOutcome.failed);
      expect(engine.result!.stars, 0);
      expect(engine.result!.earningsJenehat, 0);
      expect(engine.step(), isEmpty);
      expect(engine.state.tMs, 363, reason: 'the clock stops');
      engine.rejects(const PickFromTray(100), RejectionCode.wrongStatus);
    });

    test('a positive reputation never fails', () {
      final engine = startTrip(_definition)
        ..debugEdit((tx) => tx.reputation = 1);
      engine.step();
      expect(engine.status, TripStatus.running);
    });
  });

  test('the engine is built from definitions in content_models', () {
    final engine = TripEngine.start(
      _definition,
      defaultParams(LineId.lineGamaa),
    );
    expect(engine.state.schedule.single.atMs, 30000);
  });

  test('the events of step and stepTo are unmodifiable', () {
    final engine = startTrip(
      (TripBuilder()
            ..station('gamaa', 30)
            ..passenger(
              'p1',
              seat: 'A_r',
              dest: 'gamaa',
              payment: [500, 100, 100],
            ))
          .build(),
    );
    final step = engine.step();
    final stepTo = engine.stepTo(30030);
    expect(stepTo, isNotEmpty);
    expect(() => step.add(stepTo.first), throwsUnsupportedError);
    expect(stepTo.clear, throwsUnsupportedError);
  });
}
