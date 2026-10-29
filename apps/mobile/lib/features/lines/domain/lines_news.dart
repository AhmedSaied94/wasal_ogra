// What is new on Lines (specs/014-m09-lines-vehicles, contracts/lines.md
// "The «new» dot", research R8): a key for each thing a player would want
// to see there. The dot shows while one hasn't been seen.
import 'package:content_models/content_models.dart';
import 'package:wassal/core/content/domain/content_source.dart';
import 'package:wassal/core/economy/domain/wire.dart';
import 'package:wassal/core/progress/domain/playable.dart';
import 'package:wassal/core/progress/domain/player_progress.dart';
import 'package:wassal/core/progress/domain/unlocks.dart';

/// - `line:<id>`: an unlocked line, other than a start line;
/// - `story:<tripId>`: a playable story trip without a star;
/// - `vehicle:<id>`: a vehicle for sale that [jenehat] covers.
Set<String> linesNews(ContentSource c, PlayerProgress p, int jenehat) => {
  for (final line in c.lines)
    if (line.unlock.kind != UnlockKind.start && lineUnlocked(c, p, line.lineId))
      'line:${_snake(line.lineId.name)}',
  for (final line in c.lines)
    for (final trip in c.tripsOf(line.lineId))
      if (trip.kind == TripKind.story &&
          !p.finished(trip.tripId) &&
          tripPlayable(c, p, trip.tripId))
        'story:${trip.tripId}',
  for (final vehicle in c.vehicles)
    if (vehicleSale(c, p, vehicle.vehicleId) case ForSale(:final priceJenehat)
        when jenehat >= priceJenehat)
      'vehicle:${vehicleWire[vehicle.vehicleId]}',
};

/// A content enum's name as its wire name: `lineGamaa` → `line_gamaa`.
String _snake(String name) =>
    name.replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]!.toLowerCase()}');
