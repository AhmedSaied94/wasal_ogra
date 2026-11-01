// A story rider in the scene (specs/015-m10-apartment-story, contracts/
// story-trip.md "Riders in the scene"): a character who sits in a seat no
// passenger names. It is drawn as a passenger is, by the scene's art
// factory: `Person` with the character's look, the character's own static
// art without it. It has no tag, no tap area and no patience; it never moves
// and never leaves, and only its face changes while its comment shows.
import 'package:content_models/content_models.dart';
import 'package:flame/components.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/content/domain/story_characters.dart';
import 'package:wassal/core/theme/components/characters.dart';
import 'package:wassal/features/trip/domain/looks.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';
import 'package:wassal/features/trip/presentation/scene/passenger_art.dart';
import 'package:wassal/features/trip/presentation/scene/trip_game.dart';

/// [character]'s art as a seat's look: its `Person` look number and its own
/// static drawing, which shares the passengers' view box.
Look riderLook(StoryCharacter character) {
  final art = storyCharacterArt(character);
  return Look(
    id: art,
    labelKey: passengerLabelKey,
    rive: CharacterAvatar.looks[art] ?? 0,
    asset: CharacterAvatar.path(art),
  );
}

/// Every story character's look, for the static art to decode ahead.
List<Look> get riderLooks => [
  for (final character in StoryCharacter.values) riderLook(character),
];

/// What a rider shows when nothing is happening: calm, aboard, going
/// nowhere.
PassengerView _calm(StoryRider rider) => PassengerView(
  passengerId: 'rider-${rider.seat}',
  seatId: rider.seat,
  presence: PresenceView.aboard,
  look: riderLook(rider.character),
  slot: null,
  mood: 0,
  talking: false,
  asleep: false,
  waking: false,
  headphones: false,
  attentive: false,
  nearStopPulse: false,
  dropMeHere: false,
  ledgerBadge: null,
  outcome: null,
);

class RiderComponent extends Component with HasGameReference<TripGame> {
  RiderComponent(this.rider, this.seat);

  final StoryRider rider;
  final Seat seat;

  PassengerArt? _art;

  /// What [_art] was made by, and whether under reduced motion, which draws
  /// the static art: a change makes it again.
  PassengerArtFactory? _artFactory;
  bool _artReduced = false;
  bool _surprised = false;

  /// Where the rider is drawn now, or null before the scene has a size.
  Rect? get artBox {
    final head = game.layout?.seats[seat.seatId]?.head;
    if (head == null || _art == null) return null;
    return Rect.fromLTWH(head.left, head.top, head.width, head.height);
  }

  /// Whether its `surprised` face is on, for tests.
  @visibleForTesting
  bool get surprised => _surprised;

  /// What draws it now, for tests.
  @visibleForTesting
  PassengerArt? get art => _art;

  @override
  void update(double dt) {
    if (_art == null ||
        !identical(_artFactory, game.art) ||
        _artReduced != game.reduceMotion) {
      _art?.dispose();
      _artFactory = game.art;
      _artReduced = game.reduceMotion;
      _art = game.art.create(
        riderLook(rider.character),
        row: seat.row,
        reduceMotion: _artReduced,
      )..update(_calm(rider));
      _surprised = false;
    }
    // «surprised» while the rider's own comment shows.
    final speaking = game.view?.riderBubble?.seatId == seat.seatId;
    if (speaking != _surprised) {
      _surprised = speaking;
      _art?.surprise(on: speaking);
    }
    _art
      ?..reduceMotion = game.reduceMotion
      ..advance(dt);
  }

  @override
  void render(Canvas canvas) {
    final box = artBox;
    if (box == null) return;
    _art?.render(canvas, box);
  }

  @override
  void onRemove() {
    _art?.dispose();
    _art = null;
    super.onRemove();
  }
}
