// The one start path (specs/013-m08-home-result, contracts/home.md
// "startNextTrip"; specs/014-m09-lines-vehicles, contracts/line-details.md
// "Starting a trip"): nothing for a trip that may not start, the fuel sheet
// on an empty tank, and the card where the start came from.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/config/tunable.dart';
import 'package:wassal/core/economy/economy_providers.dart';
import 'package:wassal/features/home/application/checkpoint.dart';
import 'package:wassal/features/home/application/start_next_trip.dart';
import 'package:wassal/features/lines/presentation/lines_screen.dart';
import 'package:wassal/features/pre_trip/application/card_mode_provider.dart';

import '../../../helpers/lines.dart';
import '../../../helpers/memory_settings_store.dart';
import '../../../helpers/progress.dart';
import '../../../helpers/synthetic_packs.dart';

/// A checkpoint a test holds open.
final class _Checkpoint implements BetweenTripsCheckpoint {
  int passes = 0;
  var _gate = Completer<void>()..complete();

  void hold() => _gate = Completer<void>();

  void open() => _gate.complete();

  @override
  Future<void> pass() {
    passes++;
    return _gate.future;
  }
}

String _t(String line, int n) => '$line.${n.toString().padLeft(2, '0')}';

/// خط الجامعة open at trip 12, the card always shown.
Future<ProviderContainer> _app(
  WidgetTester tester, {
  int liters = 5,
  List<Override> overrides = const [],
  bool newPlayer = false,
}) async {
  final (container, _) = await pumpLinesApp(
    tester,
    state: playerState(
      liters: liters,
      stars: {
        'line_hay.01': 1,
        'line_hay.02': 1,
        for (var n = 1; n <= 11; n++) _t('line_gamaa', n): 2,
      },
      owned: {microOld},
    ),
    settingsStore: MemorySettingsStore({
      PreTripCardModeNotifier.key: PreTripCardMode.always.wire,
    }),
    overrides: overrides,
    newPlayer: newPlayer,
  );
  return container;
}

Future<bool> _start(WidgetTester tester, String tripId, StartFrom from) async {
  final element = tester.element(find.byType(LinesScreen));
  final started = await startNextTrip(
    element,
    element as WidgetRef,
    tripId: tripId,
    from: from,
  );
  await tester.pumpAndSettle();
  return started;
}

void main() {
  testWidgets('from Lines: the card under its line\'s details', (tester) async {
    final container = await _app(tester);
    expect(await _start(tester, 'line_gamaa.12', StartFrom.lines), isTrue);
    expect(locationOf(container), '/lines/line_gamaa/pre-trip/line_gamaa.12');
  });

  testWidgets('from Lines, the line is the trip\'s own', (tester) async {
    final container = await _app(tester);
    expect(await _start(tester, 'line_hay.01', StartFrom.lines), isTrue);
    expect(locationOf(container), '/lines/line_hay/pre-trip/line_hay.01');
  });

  testWidgets('from Home and the result: the card over Home', (tester) async {
    final container = await _app(tester);
    expect(await _start(tester, 'line_gamaa.12', StartFrom.home), isTrue);
    expect(locationOf(container), '/home/pre-trip/line_gamaa.12');
    final again = await _app(tester);
    expect(await _start(tester, 'line_gamaa.12', StartFrom.result), isTrue);
    expect(locationOf(again), '/home/pre-trip/line_gamaa.12');
  });

  testWidgets('a trip that may not start goes nowhere', (tester) async {
    final container = await _app(tester);
    for (final trip in [
      'line_gamaa.13', // after the next
      'line_gamaa.20', // a story trip whose chapter isn't complete
      'line_souq.01', // a locked line
      'line_x.01', // unknown
    ]) {
      expect(
        await _start(tester, trip, StartFrom.lines),
        isFalse,
        reason: trip,
      );
      expect(locationOf(container), '/lines', reason: trip);
    }
  });

  testWidgets('an empty tank opens the fuel sheet', (tester) async {
    final container = await _app(tester, liters: 0);
    expect(await _start(tester, 'line_gamaa.12', StartFrom.lines), isTrue);
    expect(locationOf(container), fuelSheetLocation);
  });

  testWidgets('from Lines, a tutorial trip in the first session goes straight '
      'to the trip (T107)', (tester) async {
    // hay .01 and .02 are done, so the session is under way and .03 is its
    // next trip: no card, as from Home.
    final container = await _app(tester, newPlayer: true);
    expect(await _start(tester, 'line_hay.03', StartFrom.lines), isTrue);
    expect(locationOf(container), '/trip/line_hay.03');
  });

  testWidgets('from Lines, a second tap while the checkpoint holds does '
      'nothing (T107)', (tester) async {
    final checkpoint = _Checkpoint()..hold();
    final container = await _app(
      tester,
      overrides: [betweenTripsCheckpointProvider.overrideWithValue(checkpoint)],
    );
    final element = tester.element(find.byType(LinesScreen));
    final ref = element as WidgetRef;
    final first = startNextTrip(
      element,
      ref,
      tripId: 'line_gamaa.12',
      from: StartFrom.lines,
    );
    expect(checkpoint.passes, 1);
    expect(
      await startNextTrip(
        element,
        ref,
        tripId: 'line_gamaa.12',
        from: StartFrom.lines,
      ),
      isFalse,
    );
    expect(checkpoint.passes, 1);
    expect(locationOf(container), '/lines');
    checkpoint.open();
    expect(await first, isTrue);
    await tester.pumpAndSettle();
    expect(locationOf(container), '/lines/line_gamaa/pre-trip/line_gamaa.12');
  });

  testWidgets('a story trip the port accepts but the phone rules refuse '
      'starts nothing and spends no fuel (T107)', (tester) async {
    // .17 done, no shabka: the port unlocks .18, the phone's story rule
    // waits for ch3.
    final (container, _) = await pumpLinesApp(
      tester,
      pack: draftShaped(),
      state: playerState(
        stars: {for (var n = 1; n <= 17; n++) _t('line_gamaa', n): 1},
        owned: {microOld},
      ),
    );
    final before = container.read(economyViewProvider).fuel.liters;
    expect(await _start(tester, 'line_gamaa.18', StartFrom.lines), isFalse);
    expect(locationOf(container), '/lines');
    expect(container.read(economyViewProvider).fuel.liters, before);
  });
}
