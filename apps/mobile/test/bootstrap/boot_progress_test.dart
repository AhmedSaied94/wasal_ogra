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
import 'package:wassal/core/art/rive_scenes.dart';

import '../helpers/account.dart';
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
      ...accountTestOverrides(),
      ...extra,
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('BootProgress', () {
    test('seven steps, in boot order, the art then the account last', () {
      expect(BootProgress.steps, [
        BootStep.settings,
        BootStep.tunables,
        BootStep.content,
        BootStep.database,
        BootStep.economy,
        BootStep.art,
        BootStep.account,
      ]);
    });

    test('value is done / 7', () {
      const none = BootProgress();
      expect(none.value, 0);
      final two = none.withDone(BootStep.content).withDone(BootStep.settings);
      expect(two.value, 2 / 7);
      expect(two.withDone(BootStep.content).value, 2 / 7, reason: 'once');
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
          BootStep.account,
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
    test('marks its six steps done, and leaves the account to boot', () async {
      final container = _container([]);
      expect(container.read(bootProgressProvider).value, 0);
      await container.read(appStartupProvider.future);
      final progress = container.read(bootProgressProvider);
      expect(
        progress.done,
        BootProgress.steps.toSet().difference({BootStep.account}),
      );
      expect(progress.value, 6 / 7);
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

    // specs/012.5-m22-animated-scenes, contracts/rive-scenes.md "Loading".
    test('the art step waits for both files', () async {
      final scenes = Completer<RiveArt>();
      final container = _container([
        riveArtProvider.overrideWith((ref) async => const RiveArt.none()),
        riveScenesProvider.overrideWith((ref) => scenes.future),
      ]);
      final startup = container.read(appStartupProvider.future);
      await container.read(riveArtProvider.future);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(
        container.read(bootProgressProvider).done,
        isNot(contains(BootStep.art)),
      );
      scenes.complete(const RiveArt.none());
      await startup;
      expect(container.read(bootProgressProvider).done, contains(BootStep.art));
    });

    test('a missing scenes file records a problem, and boot goes on', () async {
      final container = _container([
        riveScenesProvider.overrideWith(
          (ref) => loadRiveArt(
            contract: sceneContract,
            asset: 'assets/rive/missing.riv',
          ),
        ),
      ]);
      await container.read(appStartupProvider.future);
      final progress = container.read(bootProgressProvider);
      expect(progress.done, contains(BootStep.art));
      expect(progress.failed, isNull);
      final scenes = container.read(riveScenesProvider).requireValue;
      expect(scenes.file, isNull);
      expect(scenes.problems.single, startsWith('assets/rive/missing.riv: '));
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
    expect(container.read(bootProgressProvider).value, 6 / 7);
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
