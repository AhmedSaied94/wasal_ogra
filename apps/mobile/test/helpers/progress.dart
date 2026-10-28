// Progress test helpers (specs/013-m08-home-result/tasks.md T004): packs
// changed from the sample, as `test_unlocks.py` changes its rules document,
// and players by best stars and ownership.
import 'dart:convert';

import 'package:content_models/content_models.dart';
import 'package:wassal/core/content/domain/content_source.dart';
import 'package:wassal/core/content/pack_content_source.dart';
import 'package:wassal/core/progress/domain/player_progress.dart';

import 'content.dart';
import 'synthetic_packs.dart';

/// The sample pack's JSON, deep-copied so a test can change it.
Map<String, Object?> sampleJsonCopy() =>
    (jsonDecode(jsonEncode(samplePackJson())) as Map<String, dynamic>)
        .cast<String, Object?>();

/// The sample with [change] applied to its JSON. Built straight from the
/// models, without the decoder's checks, as the Python tests change the
/// rules document without validating it.
ContentSource sampleWith(void Function(Map<String, Object?> json) change) {
  final json = sampleJsonCopy();
  change(json);
  return PackContentSource(Pack.fromJson(json));
}

/// [json]'s list [key], as maps a test can change in place.
List<Map<String, Object?>> entries(Map<String, Object?> json, String key) => [
  for (final item in json[key]! as List<Object?>)
    (item! as Map<String, Object?>),
];

/// The entry of [json]'s list [key] whose [idKey] is [id].
Map<String, Object?> entry(
  Map<String, Object?> json,
  String key,
  String idKey,
  String id,
) => entries(json, key).firstWhere((e) => e[idKey] == id);

/// A player with these best stars and these owned `(kind, sku id)` pairs.
PlayerProgress player([
  Map<String, int> stars = const {},
  Set<(SkuKind, String)> owned = const {},
]) => PlayerProgress(bestStars: stars, owned: owned);

const microOld = (SkuKind.vehicle, 'micro_old');
const shabka = (SkuKind.chapter, 'ch3_shabka');
const salonNish = (SkuKind.item, 'salon.nish');
const salonSitara = (SkuKind.item, 'salon.sitara');
const salon = {salonNish, salonSitara};

/// `HAY_DONE`: both regular trips of the sample's line_hay finished.
const hayDone = {'line_hay.01': 1, 'line_hay.02': 3};

ContentSource? _progression;

/// [progressionPackJson] as content: several lines, a story trip mid-line
/// whose chapter is locked, and a line the sweeps never open.
ContentSource progressionContent() =>
    _progression ??= PackContentSource(Pack.fromJson(progressionPackJson()));

/// Every set of finished trips reachable from a new player by finishing
/// startable trips, at most [depth] of them, with each trip at one star.
List<Set<String>> reachableStates(
  ContentSource content, {
  required bool Function(PlayerProgress player, String tripId) startable,
  int depth = 6,
}) {
  final all = [
    for (final line in content.lines)
      for (final trip in content.tripsOf(line.lineId)) trip.tripId,
  ];
  final seen = <String>{};
  final states = <Set<String>>[];
  var frontier = [<String>{}];
  for (var level = 0; level <= depth; level++) {
    final next = <Set<String>>[];
    for (final state in frontier) {
      final key = (state.toList()..sort()).join(' ');
      if (!seen.add(key)) continue;
      states.add(state);
      final p = player({for (final id in state) id: 1});
      for (final id in all) {
        if (!state.contains(id) && startable(p, id)) next.add({...state, id});
      }
    }
    frontier = next;
  }
  return states;
}
