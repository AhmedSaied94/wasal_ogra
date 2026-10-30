// The apartment's drawings (specs/015-m10-apartment-story, research R17).
// The same pattern as `PanelArt`: a const map from the content's slug to the
// asset the app ships, copied from `docs/design` by
// `tool/design/sync_assets.dart` and checked by `design_assets_test`. A slug
// with no drawing returns null, so the caller draws its token fallback
// (`RoomFallback`, `PieceFallback`, the vehicle sprite) instead. Art ships in
// the app, not in packs, so a missing drawing never blocks a screen.
class ApartmentArt {
  const ApartmentArt._();

  /// The drawn rooms, by `Room.art`.
  static const _rooms = <String, String>{};

  /// The drawn pieces, by `ItemVariant.art`.
  static const _pieces = {
    'antreeh_modern':
        'assets/illustrations/apartment/pieces/antreeh_modern.svg',
  };

  /// The drawn goals, by `Chapter.goal_art`.
  static const _goals = {
    'goal_shabka': 'assets/illustrations/apartment/goals/goal_shabka.svg',
  };

  /// The teaser's empty room (R17).
  static const teaserRoom = 'assets/illustrations/apartment/teaser_room.svg';

  /// The asset drawn for [slug] as a room, or null.
  static String? room(String slug) => _rooms[slug];

  /// The asset drawn for [slug] as a piece, or null.
  static String? piece(String slug) => _pieces[slug];

  /// The asset drawn for [slug] as a goal, or null.
  static String? goal(String slug) => _goals[slug];
}
