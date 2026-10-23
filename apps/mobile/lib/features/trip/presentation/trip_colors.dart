// The trip's colours by role (specs/008.5-m21-design-refresh, HANDOFF §3.4):
// the stations, the denominations and the money notes, from the design
// tokens' `station`, `denomination` and `money_note` groups. The scene and
// the dashboard read `ColorTokens.scene*` and `ColorTokens.dashboard*`.
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';

/// A money note's fill, lip and digits.
typedef NoteColors = ({Color bg, Color lip, Color text});

abstract final class TripColors {
  /// A stop's fill and letter colour by its slot, in alighting order.
  static StationPair station(int slot) =>
      StationColors.all[slot % StationColors.all.length];

  /// A coin's or a note's colour in the drawer and the hand.
  static Color denomination(int piasters) => switch (piasters) {
    50 => ColorTokens.denom050,
    100 => ColorTokens.denom1,
    500 => ColorTokens.denom5,
    1000 => ColorTokens.denom10,
    2000 => ColorTokens.denom20,
    5000 => ColorTokens.denom50,
    10000 => ColorTokens.denom100,
    _ => ColorTokens.denom200,
  };

  /// Coins are round in the drawer and the hand; notes are small rects.
  static bool isCoin(int piasters) => piasters < 500;

  static const fare = (
    bg: ColorTokens.noteFare,
    lip: ColorTokens.noteFareLip,
    text: ColorTokens.noteFareText,
  );
  static const change = (
    bg: ColorTokens.noteChange,
    lip: ColorTokens.noteChangeLip,
    text: ColorTokens.noteChangeText,
  );
  static const blocked = (
    bg: ColorTokens.noteBlocked,
    lip: ColorTokens.noteBlockedLip,
    text: ColorTokens.noteBlockedText,
  );
  static const inHand = (
    bg: ColorTokens.noteInHand,
    lip: ColorTokens.noteInHandLip,
    text: ColorTokens.noteInHandText,
  );
}
