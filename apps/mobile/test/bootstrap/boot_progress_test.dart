import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/bootstrap/boot_progress.dart';
import 'package:wassal/bootstrap/flavor.dart';
import 'package:wassal/bootstrap/startup.dart';
import 'package:wassal/core/config/config_providers.dart';
import 'package:wassal/core/economy/economy_providers.dart';
import 'package:wassal/core/art/rive_art.dart';

import '../helpers/content.dart';
import '../helpers/economy.dart';
import '../helpers/memory_settings_store.dart';

// The loading bar's progress (data-model.md "BootProgress"; research R6):
// each boot step reports as it finishes, a failure names its step, and the
// retry starts over.

ProviderContainer _container(List<Override> extra, {List<Override>? economy}) {
  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      flavorProvider.overrideWithValue(Flavor.dev),
      settingsStoreProvider.overrideWith((ref) async => MemorySettingsStore()),
      ...contentTestOverrides(),
      ...economy ?? economyTestOverrides(),
      ...extra,
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('BootProgress', () {
    test('six steps, in boot order, the art last', () {
      expect(BootProgress.steps, [
        BootStep.settings,
        BootStep.tunables,
        BootStep.content,
        BootStep.database,
        BootStep.economy,
        BootStep.art,
      ]);
    });

    test('value is done / 6', () {
      const none = BootProgress();
      expect(none.value, 0);
      final two = none.withDone(BootStep.content).withDone(BootStep.settings);
      expect(two.value, 2 / 6);
      expect(two.withDone(BootStep.content).value, 2 / 6, reason: 'once');
      var all = none;
      for (final step in BootProgress.steps) {
        all = all.withDone(step);
      }
      expect(all.value, 1);
    });

    test('a failure names its step and keeps what was done', () {
      final p = const BootProgress()
          .withDone(BootStep.settings)
          .withFailure(BootStep.tunables);
      expect(p.failed, BootStep.tunables);
      expect(p.done, {BootStep.settings});
    });
  });

  group('trackBootSteps', () {
    test(
      'reports each step as it finishes, in the order they finish',
      () async {
        final gates = {
          for (final s in BootProgress.steps) s: Completer<void>(),
        };
        final reported = <BootStep>[];
        final all = trackBootSteps(
          {
            for (final MapEntry(:key, :value) in gates.entries)
              key: value.future,
          },
          onDone: reported.add,
          onFailed: (_) => fail('nothing fails'),
        );
        const order = [
          BootStep.content,
          BootStep.art,
          BootStep.settings,
          BootStep.economy,
          BootStep.tunables,
          BootStep.database,
        ];
        for (final (i, step) in order.indexed) {
          gates[step]!.complete();
          await pumpEventQueue();
          expect(reported, order.take(i + 1));
        }
        await all;
      },
    );

    test('a failing step is reported, and the wait fails', () async {
      final failed = <BootStep>[];
      final all = trackBootSteps(
        {
          BootStep.settings: Future<void>.value(),
          BootStep.tunables: Future<void>.error(StateError('no config')),
        },
        onDone: (_) {},
        onFailed: failed.add,
      );
      await expectLater(all, throwsStateError);
      expect(failed, [BootStep.tunables]);
    });
  });

  group('appStartup', () {
    test('marks all six steps done', () async {
      final container = _container([]);
      expect(container.read(bootProgressProvider).value, 0);
      await container.read(appStartupProvider.future);
      final progress = container.read(bootProgressProvider);
      expect(progress.done, BootProgress.steps.toSet());
      expect(progress.value, 1);
      expect(progress.failed, isNull);
    });

    test('a missing Rive file records a problem, and boot goes on', () async {
      final container = _container([
        riveArtProvider.overrideWith(
          (ref) => loadRiveArt(asset: 'assets/rive/missing.riv'),
        ),
      ]);
      await container.read(appStartupProvider.future);
      final progress = container.read(bootProgressProvider);
      expect(progress.done, contains(BootStep.art));
      expect(progress.failed, isNull);
      final art = container.read(riveArtProvider).requireValue;
      expect(art.file, isNull);
      expect(art.usable, isEmpty);
      expect(art.problems.single, startsWith('assets/rive/missing.riv'));
    });

    test('a failing step sets failed to it', () async {
      final container = _container([
        tunableLayersProvider.overrideWith(
          (ref) => Future.error(StateError('no tunables')),
        ),
      ]);
      await expectLater(
        container.read(appStartupProvider.future),
        throwsStateError,
      );
      final progress = container.read(bootProgressProvider);
      expect(progress.failed, BootStep.tunables);
      expect(progress.done, isNot(contains(BootStep.tunables)));
    });

    test('the database step waits for the database', () async {
      final gate = Completer<void>();
      final container = _container(
        [],
        economy: [
          uptimeSourceProvider.overrideWithValue(FakeUptimeSource()),
          databaseOpenerProvider.overrideWithValue(() async {
            await gate.future;
            return NativeDatabase.memory();
          }),
        ],
      );
      final startup = container.read(appStartupProvider.future);
      await pumpEventQueue();
      expect(
        container.read(bootProgressProvider).done,
        isNot(contains(BootStep.database)),
      );
      gate.complete();
      await startup;
      expect(
        container.read(bootProgressProvider).done,
        contains(BootStep.database),
      );
    });
  });

  testWidgets('retryAppStartup resets done', (tester) async {
    final container = _container([]);
    await container.read(appStartupProvider.future);
    expect(container.read(bootProgressProvider).value, 1);
    late WidgetRef widgetRef;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder: (context, ref, _) {
            widgetRef = ref;
            return const SizedBox();
          },
        ),
      ),
    );
    retryAppStartup(widgetRef);
    expect(container.read(bootProgressProvider).done, isEmpty);
  });
}
