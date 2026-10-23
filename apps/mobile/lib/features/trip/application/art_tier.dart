// Which seats Rive draws (specs/008.5-m21-design-refresh, research R18):
// every one, the near ones, or none. The A06 measurement decides the
// default; dev and staging switch it from the debug panel, for the session
// only.
import 'package:content_models/content_models.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'art_tier.g.dart';

enum ArtTier {
  rive,

  /// The front seat and row A in Rive, the rows behind static (HANDOFF §6.4
  /// step 3).
  nearRive,
  static;

  /// Whether a passenger in [row] is drawn by Rive.
  bool drawsRow(SeatRow row) => switch (this) {
    ArtTier.rive => true,
    ArtTier.nearRive => row == SeatRow.front || row == SeatRow.a,
    ArtTier.static => false,
  };
}

@Riverpod(keepAlive: true)
class ArtTierSetting extends _$ArtTierSetting {
  @override
  ArtTier build() => ArtTier.rive;

  void select(ArtTier tier) => state = tier;
}
