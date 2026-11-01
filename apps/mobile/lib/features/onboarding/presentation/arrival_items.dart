// M07's two things that open on arrival at Home, as Home's arrival items
// (specs/013-m08-home-result, contracts/seams.md `ArrivalItem`, research R9,
// Clarifications 2026-10-28). They replace the router's `/home` redirect
// and `NameReaskHost`: a due scene and the name sheet never share an
// arrival.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/content/home_arrival.dart';
import 'package:wassal/core/routing/router.dart' show dueSceneLocation;
import 'package:wassal/features/home/application/arrival_queue.dart';
import 'package:wassal/features/onboarding/domain/first_session.dart';
import 'package:wassal/features/onboarding/onboarding_providers.dart';
import 'package:wassal/features/onboarding/presentation/name_sheet.dart';

/// Rank 10: the scene due after a tutorial trip (M07 FR-031). `ScenePage`
/// runs M07's `afterScene` step (the first notification ask) before it
/// returns to Home, so the ask is part of this item.
final class DueSceneArrival implements ArrivalItem {
  const DueSceneArrival();

  @override
  int get rank => 10;

  static String? _due(ProviderContainer container) =>
      switch (container.read(firstSessionProvider).onArrivalAtHome()) {
        DueScene(:final sceneId) => sceneId,
        null => null,
      };

  @override
  bool isDue(ProviderContainer container) => _due(container) != null;

  @override
  Future<void> open(BuildContext context, ProviderContainer container) {
    final sceneId = _due(container);
    if (sceneId == null) return Future.value();
    final router = GoRouter.of(context);
    // M10: M07's player in the first session, the story viewer after it.
    final location = dueSceneLocation(
      sceneId,
      HomeArrival.homePath,
      firstSession: container.read(firstSessionProvider).inFirstSession,
    );
    final left = untilLeft(router, Uri.parse(location).path);
    unawaited(router.push<void>(location));
    return left;
  }
}

/// Rank 20: the name sheet, for a name the server refused or one never
/// given once a trip has started, at most once a launch (M07 FR-018).
final class NameSheetArrival implements ArrivalItem {
  const NameSheetArrival();

  @override
  int get rank => 20;

  @override
  bool isDue(ProviderContainer container) =>
      container.read(firstSessionProvider).askName &&
      !container.read(nameAskedProvider);

  @override
  Future<void> open(BuildContext context, ProviderContainer container) {
    container.read(nameAskedProvider.notifier).done = true;
    final session = container.read(firstSessionProvider);
    return showNameSheet(context, refused: session.facts.nameRefused);
  }
}
