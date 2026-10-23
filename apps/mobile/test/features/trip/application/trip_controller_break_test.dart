import 'dart:convert';

import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/features/trip/application/trip_controller.dart';
import 'package:wassal/features/trip/domain/trip_facts.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';

import '../../../helpers/economy.dart';
import '../../../helpers/trip.dart';

// «حد معاه فكة؟» and the rejections said in words (tasks.md T074,
// contracts/trip-view.md "Rejections").

/// A sample trip whose drawer holds notes to break: 10 and 20.
const _trip = 'line_gamaa.02';

List<Object?> lastCommand(TripController c) =>
    c.engine!.commandLog.last.toJson().sublist(1);

Future<TripController> running(TestEconomy economy) async {
  final c = testController(economy);
  await c.open(_trip);
  advanceMs(c, 1000);
  return c;
}

void main() {
  test('pick mode lights the notes the engine would break', () async {
    final c = await running(await testEconomy());
    expect(c.view!.tray.where((s) => s.breakable), isEmpty);

    c.startBreak();
    expect(c.view!.breakMode, isTrue);
    final min = c.session!.facts.params.tripBreakMinPiasters;
    final tray = c.engine!.state.tray;
    final lit = {
      for (final slot in c.view!.tray)
        if (slot.breakable) slot.denomination,
    };
    expect(lit, {
      for (final d in trayDenominations)
        if (d >= min && tray.count(d) > 0) d,
    });
    expect(lit, isNotEmpty);
    // The clock runs on.
    final tMs = c.engine!.state.tMs;
    advanceMs(c, 330);
    expect(c.engine!.state.tMs, tMs + 330);
  });

  test('picking a note asks for the break', () async {
    final c = await running(await testEconomy());
    final left = c.view!.breakButton.left;
    c
      ..startBreak()
      ..pickBreak(1000);
    expect(lastCommand(c), ['RequestBreak', 1000]);
    expect(c.view!.breakMode, isFalse);
    expect(c.view!.breakButton.left, left - 1);
    expect(c.engine!.state.tray.count(1000), 0);
  });

  test('cancelling leaves pick mode without a command', () async {
    final c = await running(await testEconomy());
    final commands = c.engine!.commandLog.length;
    c
      ..startBreak()
      ..cancelBreak();
    expect(c.view!.breakMode, isFalse);
    expect(c.engine!.commandLog, hasLength(commands));
  });

  test('the button counts down, turns off at zero, then says why', () async {
    final c = await running(await testEconomy());
    final max = c.view!.breakButton.left;
    expect(max, greaterThan(0));
    expect(c.view!.breakButton.enabled, isTrue);
    for (final note in [1000, 2000].take(max)) {
      c
        ..startBreak()
        ..pickBreak(note);
    }
    expect(c.view!.breakButton.left, 0);
    expect(c.view!.breakButton.enabled, isFalse);

    c.startBreak();
    expect(c.view!.breakMode, isFalse);
    final rejection = c.view!.rejection!;
    expect(rejection.code, RejectionCode.breakLimit);
    expect(rejection.untilMs, c.engine!.state.tMs + rejectionLineMs);
    // Gone after its time.
    advanceMs(c, rejectionLineMs + 33);
    expect(c.view!.rejection, isNull);
  });

  test('a change request the drawer can\'t break is said in words', () async {
    final fixture = loadFixture('event__change_request');
    final json = jsonDecode(
      jsonEncode(fixture.definition.toJson()),
    ) as Map<String, Object?>;
    // Nothing that adds up to the 10 they hold out, and no fare in yet.
    json['initial_tray'] = {'500': 1};
    json['passengers'] = [
      for (final p
          in (json['passengers']! as List<Object?>)
              .cast<Map<String, Object?>>())
        {...p, 'pays_at_seconds': 30},
    ];
    final c = testController(
      await testEconomy(),
      fixed: FixedTrip(
        definition: TripDefinition.fromJson(json),
        params: fixture.params,
        seed: fixture.seed,
      ),
    );
    await c.open(fixture.definition.tripId);
    while (c.view!.choices.whereType<ChangeRequestChoice>().isEmpty) {
      advanceMs(c, 33);
    }
    final commands = c.engine!.commandLog.length;

    c.answerChangeRequest('p1', agree: true);
    expect(c.engine!.commandLog, hasLength(commands));
    expect(c.view!.rejection?.code, RejectionCode.cannotMakeChange);
    // Still asked.
    expect(c.view!.choices.whereType<ChangeRequestChoice>(), hasLength(1));
  });
}
