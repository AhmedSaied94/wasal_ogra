// Recording a scene (specs/015-m10-apartment-story, contracts/story-flow.md
// "Recording a scene", T075): M07's flag and one `story_progress`, with one
// held request per scene.
import 'dart:async';

import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/economy/economy.dart' hide Owned;
import 'package:wassal/core/progress/domain/player_progress.dart';
import 'package:wassal/features/onboarding/domain/first_session.dart';
import 'package:wassal/features/onboarding/onboarding_providers.dart';
import 'package:wassal/features/story/application/story_service.dart';

import '../../../helpers/economy.dart';
import '../../../helpers/progress.dart';

final class _FakeEconomy implements Economy {
  _FakeEconomy(this.outcomes);

  final List<FutureOr<OpOutcome>> outcomes;
  final calls = <(TxnId, ChapterId, String)>[];
  var _next = 300;

  @override
  TxnId newRequestId() => txnIdOf(_next++);

  @override
  Future<OpOutcome> recordScene(
    TxnId id, {
    required ChapterId chapterId,
    required String sceneId,
  }) async {
    calls.add((id, chapterId, sceneId));
    return outcomes.removeAt(0);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Flags extends FirstSessionFlagsNotifier {
  _Flags([this._flags = const FirstSessionFlags()]);

  final FirstSessionFlags _flags;
  final marked = <String>[];

  @override
  FirstSessionFlags get current => _flags;

  @override
  Future<void> markSceneSeen(String sceneId) async => marked.add(sceneId);
}

late final LedgerOp _anyOp;
late final EconomyView _anyView;

OpApplied _applied() => OpApplied(op: _anyOp, view: _anyView, repeated: false);

void main() {
  final content = sampleWith((_) {});

  setUpAll(() async {
    final e = await testEconomy(content: content);
    final outcome = await e.service.recordScene(
      e.service.newRequestId(),
      chapterId: ChapterId.ch1FirstJob,
      sceneId: 'opening',
    ) as OpApplied;
    _anyOp = outcome.op;
    _anyView = outcome.view;
    await e.db.close();
  });

  StoryService serviceFor(
    _FakeEconomy economy,
    _Flags flags, {
    PlayerProgress? progress,
    Set<String> seen = const {},
  }) => StoryService(
    economy,
    content,
    flags,
    () => progress ?? player(),
    () => seen,
  );

  test('a first view marks M07\'s flag and sends one story_progress', () async {
    final economy = _FakeEconomy([_applied()]);
    final flags = _Flags();
    await serviceFor(economy, flags).recordSeen('opening');
    expect(flags.marked, ['opening']);
    expect(economy.calls.single.$2, ChapterId.ch1FirstJob);
    expect(economy.calls.single.$3, 'opening');
  });

  test('a replay sends nothing, and still marks the flag', () async {
    final economy = _FakeEconomy([]);
    final flags = _Flags();
    await serviceFor(economy, flags, seen: {'opening'}).recordSeen('opening');
    expect(economy.calls, isEmpty);
    expect(flags.marked, ['opening']);
  });

  test('a locked scene and an unknown id send nothing', () async {
    final economy = _FakeEconomy([]);
    final flags = _Flags();
    final service = serviceFor(economy, flags);
    await service.recordSeen('the_stand');
    await service.recordSeen('nope');
    expect(economy.calls, isEmpty);
    expect(flags.marked, isEmpty);
  });

  test('a failed write keeps the id for the next call', () async {
    final economy = _FakeEconomy([const OpWriteFailed(), _applied()]);
    final flags = _Flags();
    final service = serviceFor(economy, flags);
    await service.recordSeen('opening');
    await service.recordSeen('opening');
    expect(economy.calls, hasLength(2));
    expect(economy.calls[0].$1, economy.calls[1].$1);
  });

  test('backfill sends only the scenes M07 saw', () async {
    final economy = _FakeEconomy([_applied(), _applied()]);
    final flags = _Flags(
      const FirstSessionFlags(
        openingDoneAtMs: 5,
        scenesSeen: ['opening', 'the_stand'],
      ),
    );
    final service = serviceFor(
      economy,
      flags,
      progress: player({'line_hay.03': 3}),
    );
    await service.backfill();
    expect(economy.calls.map((c) => c.$3), ['opening', 'the_stand']);
    await StoryService(
      economy,
      content,
      flags,
      () => player({'line_hay.03': 3}),
      () => {'opening', 'the_stand'},
    ).backfill();
    expect(economy.calls, hasLength(2));
  });
}
