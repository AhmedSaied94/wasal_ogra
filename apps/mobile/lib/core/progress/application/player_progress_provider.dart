// The player as the progression rules read them (specs/013-m08-home-result,
// contracts/progress-rules.md "Inputs"), built from the economy's view and
// the active pack, and rebuilt when either changes.
import 'package:content_models/content_models.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wassal/core/content/content_providers.dart';
import 'package:wassal/core/content/domain/content_source.dart';
import 'package:wassal/core/economy/domain/wire.dart';
import 'package:wassal/core/economy/economy.dart';
import 'package:wassal/core/economy/economy_providers.dart';
import 'package:wassal/core/progress/domain/player_progress.dart';

part 'player_progress_provider.g.dart';

/// [view]'s best stars, and what it owns of [content]'s vehicles, items
/// and chapters. The view can't list its ownership, so the pack's SKUs are
/// asked one by one; one the pack lacks can't unlock anything in it.
PlayerProgress playerProgressOf(EconomyView view, ContentSource content) =>
    _progressOf(progress: view.progress, owns: view.owns, content: content);

/// The same over the confirmed base (M10 research R6): a reward is "on its
/// way" while the projection completes a room, a chapter or a request and
/// the base doesn't.
PlayerProgress playerProgressOfConfirmed(
  ConfirmedState confirmed,
  ContentSource content,
) => _progressOf(
  progress: confirmed.progress,
  owns: confirmed.owns,
  content: content,
);

PlayerProgress _progressOf({
  required Map<String, TripProgress> progress,
  required bool Function(SkuKind kind, String skuId) owns,
  required ContentSource content,
}) => PlayerProgress(
  bestStars: {
    for (final MapEntry(:key, :value) in progress.entries) key: value.bestStars,
  },
  owned: {
    for (final vehicle in content.vehicles)
      if (owns(SkuKind.vehicle, vehicleWire[vehicle.vehicleId]!))
        (SkuKind.vehicle, vehicleWire[vehicle.vehicleId]!),
    for (final room in content.rooms)
      for (final item in content.itemsOf(room.roomId))
        if (owns(SkuKind.item, item.itemId)) (SkuKind.item, item.itemId),
    for (final chapter in content.chapters)
      if (owns(SkuKind.chapter, chapterWire[chapter.chapterId]!))
        (SkuKind.chapter, chapterWire[chapter.chapterId]!),
  },
);

@Riverpod(keepAlive: true)
PlayerProgress playerProgress(Ref ref) => playerProgressOf(
  ref.watch(economyViewProvider),
  ref.watch(contentSourceProvider),
);
