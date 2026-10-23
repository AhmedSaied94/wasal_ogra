// The station tags (layer 7, HANDOFF §3.4 `StationTag`): on each
// passenger's shoulder, the station's colour and letter, so colour is never
// the only cue (constitution XI). A tag is `hot` while their stop is next and
// they are still owed: a `danger` ring beating 1 ↔ 1.18. When they ask to get
// off here it becomes the `alightHere` star. While the ledger is open, its
// `LedgerBadge` takes the tag's place (`TripEvents` block 5).
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/trip/domain/scene_layout.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';
import 'package:wassal/features/trip/presentation/overlays/choices_layer.dart';
import 'package:wassal/features/trip/presentation/trip_colors.dart';
import 'package:wassal/features/trip/presentation/trip_motion.dart';
import 'package:wassal/features/trip/presentation/trip_scope.dart';
import 'package:wassal/features/trip/presentation/trip_text.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

/// The «هنا» star.
const hereSize = 30.0;

/// A tag, the star when [slot] is null, or the ledger's [badge].
typedef _Patch = ({
  String passengerId,
  String seatId,
  int? slot,
  bool hot,
  LedgerBadge? badge,
});

class PatchesLayer extends StatelessWidget {
  const PatchesLayer({required this.layout, super.key});

  final SceneLayout layout;

  static Key tagKey(String passengerId) => ValueKey('trip-tag-$passengerId');
  static Key hereKey(String passengerId) => ValueKey('trip-here-$passengerId');

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: TripTextScale.scope(
        context,
        child: TripSelector<List<_Patch>>(
          select: (model) => [
            for (final p in model.view?.passengers ?? const <PassengerView>[])
              if (p.presence == PresenceView.aboard)
                if (p.dropMeHere)
                  (
                    passengerId: p.passengerId,
                    seatId: p.seatId,
                    slot: null,
                    hot: true,
                    badge: null,
                  )
                else if (p.ledgerBadge case final badge?)
                  (
                    passengerId: p.passengerId,
                    seatId: p.seatId,
                    slot: p.slot,
                    hot: false,
                    badge: badge,
                  )
                else if (p.slot case final slot?)
                  (
                    passengerId: p.passengerId,
                    seatId: p.seatId,
                    slot: slot,
                    hot: p.nearStopPulse,
                    badge: null,
                  ),
          ],
          equals: listEquals,
          builder: (context, patches) => Stack(
            children: [
              for (final p in patches)
                if (layout.seats[p.seatId] case final seat?) _placed(seat, p),
            ],
          ),
        ),
      ),
    );
  }

  /// Centred on the seat's tag point, which the star and the badge share.
  Widget _placed(SeatLayout seat, _Patch p) {
    if (p.badge case final badge?) {
      return Positioned(
        left: seat.tag.x,
        top: seat.tag.y,
        child: FractionalTranslation(
          translation: const Offset(-0.5, -0.5),
          child: LedgerBadgeChip(
            key: LedgerBadgeChip.badgeKey(p.passengerId),
            badge: badge,
          ),
        ),
      );
    }
    final size = p.slot == null ? hereSize : seat.tagSize;
    return Positioned(
      left: seat.tag.x - size / 2,
      top: seat.tag.y - size / 2,
      width: size,
      height: size,
      child: switch (p.slot) {
        final slot? => StationTag(
          key: tagKey(p.passengerId),
          slot: slot,
          size: seat.tagSize,
          hot: p.hot,
        ),
        null => HereStar(key: hereKey(p.passengerId)),
      },
    );
  }
}

/// A station tag: 24 on the back row, 26 in the middle, 30 near.
class StationTag extends StatelessWidget {
  const StationTag({
    required this.slot,
    required this.size,
    this.hot = false,
    super.key,
  });

  final int slot;
  final double size;
  final bool hot;

  double get _letter => switch (size) {
    <= 24 => DesignExtras.tagLetterBack,
    <= 26 => DesignExtras.tagLetterMiddle,
    _ => DesignExtras.tagLetterNear,
  };

  @override
  Widget build(BuildContext context) {
    final colors = TripColors.station(slot);
    final tag = SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.bg,
          shape: BoxShape.circle,
          border: Border.all(
            color: ColorTokens.paper,
            width: DesignExtras.tagBorder,
            strokeAlign: BorderSide.strokeAlignInside,
          ),
          boxShadow: [hot ? RingTokens.hot.spread : DesignExtras.tagLip],
        ),
        child: Center(
          child: Text(
            AppLocalizations.of(context).stationLetter(slot),
            style: TypeTokens.label
                .weight(700)
                .copyWith(color: colors.letter, fontSize: _letter, height: 1),
          ),
        ),
      ),
    );
    if (!hot) return tag;
    return TripPulse(
      amplitude: TripMotion.hotPulseAmplitude,
      cycle: TripMotion.hotPulse,
      child: tag,
    );
  }
}

/// «هنا»: they want to get off now (`StationTag alightHere`): a `sun` star
/// with a `danger` ring, pulsing.
class HereStar extends StatelessWidget {
  const HereStar({super.key});

  @override
  Widget build(BuildContext context) {
    final star = SizedBox.square(
      dimension: hereSize,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: ColorTokens.sun,
          shape: StarBorder(
            innerRadiusRatio: 0.62,
            pointRounding: 0.3,
            valleyRounding: 0.2,
            side: BorderSide(
              color: RingTokens.hot.color,
              width: RingTokens.hot.width,
              strokeAlign: BorderSide.strokeAlignOutside,
            ),
          ),
        ),
        child: Center(
          child: Text(
            AppLocalizations.of(context).tripPatchHere,
            style: TypeTokens.label
                .weight(700)
                .copyWith(color: ColorTokens.ink, height: 1),
          ),
        ),
      ),
    );
    return TripPulse(
      amplitude: TripMotion.hotPulseAmplitude,
      cycle: TripMotion.hotPulse,
      child: star,
    );
  }
}
