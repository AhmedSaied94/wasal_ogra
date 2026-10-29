// What Lines draws (specs/014-m09-lines-vehicles, contracts/lines.md "The
// model"): the balances, the vehicle strip, the line cards and the line to
// open on. Rebuilt from the pack, the economy and the first session, so a
// sync, a rollback or a purchase redraws the screen (FR-022).
import 'package:content_models/content_models.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wassal/core/content/content_providers.dart';
import 'package:wassal/core/economy/economy_providers.dart';
import 'package:wassal/core/progress/application/player_progress_provider.dart';
import 'package:wassal/core/sync/server_status.dart';
import 'package:wassal/features/home/application/home_model.dart';
import 'package:wassal/features/home/application/last_finished_trip.dart';
import 'package:wassal/features/home/domain/next_trip.dart';
import 'package:wassal/features/lines/domain/focus_line.dart';
import 'package:wassal/features/lines/domain/line_standing.dart';
import 'package:wassal/features/lines/domain/vehicle_tiles.dart';
import 'package:wassal/features/onboarding/onboarding_providers.dart';

part 'lines_model.g.dart';

final class LinesModel {
  const LinesModel({
    required this.jenehat,
    required this.bonat,
    required this.online,
    required this.tiles,
    required this.cards,
    required this.focus,
  });

  final int jenehat;
  final int bonat;

  /// The BONAT pill links to the shop only online (FR-015).
  final bool online;

  /// In pack order.
  final List<VehicleTile> tiles;

  /// In pack order; the map draws the first at the bottom.
  final List<LineStanding> cards;

  /// The card brought into view on open (FR-010).
  final LineId? focus;

  @override
  bool operator ==(Object other) =>
      other is LinesModel &&
      other.jenehat == jenehat &&
      other.bonat == bonat &&
      other.online == online &&
      _same(other.tiles, tiles) &&
      _same(other.cards, cards) &&
      other.focus == focus;

  @override
  int get hashCode => Object.hash(
    jenehat,
    bonat,
    online,
    Object.hashAll(tiles),
    Object.hashAll(cards),
    focus,
  );
}

bool _same<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

@riverpod
LinesModel linesModel(Ref ref) {
  final content = ref.watch(contentSourceProvider);
  final view = ref.watch(economyViewProvider);
  final progress = ref.watch(playerProgressProvider);
  final next = homeNextTrip(
    content,
    progress,
    ref.watch(firstSessionProvider),
    lastFinishedTripId:
        ref.watch(lastFinishedTripProvider) ??
        lastFirstCompleted(view.progress),
  );
  return LinesModel(
    jenehat: view.jenehat,
    bonat: view.bonat,
    online: ref.watch(serverStatusProvider).reach != Reach.offline,
    tiles: vehicleTiles(content, progress),
    cards: lineStandings(content, progress),
    focus: focusLine(content, progress, next),
  );
}
