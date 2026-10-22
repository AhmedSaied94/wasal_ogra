// The station patch on each passenger's shoulder (layer 7): the station's
// color and letter, so color is never the only cue (constitution XI). It
// pulses orange when their station is next and they are still owed, and
// turns into a pulsing «هنا» star when they ask to get off here.
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/app_theme.dart';
import 'package:wassal/core/theme/tokens/typography.dart';
import 'package:wassal/features/trip/domain/scene_layout.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';
import 'package:wassal/features/trip/presentation/trip_scope.dart';
import 'package:wassal/features/trip/presentation/trip_text.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

const patchSize = 24.0;

/// The «هنا» star, big enough for its word.
const hereSize = 44.0;

/// A patch, or the star when [slot] is null.
typedef _Patch = ({String passengerId, String seatId, int? slot, bool pulse});

class PatchesLayer extends StatelessWidget {
  const PatchesLayer({required this.layout, super.key});

  final SceneLayout layout;

  static Key hereKey(String passengerId) => ValueKey('trip-here-$passengerId');

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: TripSelector<List<_Patch>>(
        select: (model) => [
          for (final p in model.view?.passengers ?? const <PassengerView>[])
            if (p.presence == PresenceView.aboard)
              if (p.dropMeHere)
                (
                  passengerId: p.passengerId,
                  seatId: p.seatId,
                  slot: null,
                  pulse: true,
                )
              else if (p.slot case final slot?)
                (
                  passengerId: p.passengerId,
                  seatId: p.seatId,
                  slot: slot,
                  pulse: p.nearStopPulse,
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
    );
  }

  /// On the shoulder: the patch's center, which the star shares.
  Widget _placed(SeatGeometry seat, _Patch p) {
    final x = seat.face.left + seat.face.width * 0.8;
    final y = seat.face.top + seat.face.height * 0.74;
    return switch (p.slot) {
      final slot? => Positioned(
        left: x - patchSize / 2,
        top: y - patchSize / 2,
        child: StationPatch(slot: slot, pulse: p.pulse),
      ),
      null => Positioned(
        left: x - hereSize / 2,
        top: y - hereSize / 2,
        child: HereStar(key: hereKey(p.passengerId)),
      ),
    };
  }
}

/// «هنا»: they want to get off now.
class HereStar extends StatelessWidget {
  const HereStar({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final star = SizedBox.square(
      dimension: hereSize,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: tokens.danger,
          shape: StarBorder(
            innerRadiusRatio: 0.62,
            pointRounding: 0.3,
            valleyRounding: 0.2,
            side: BorderSide(color: tokens.hibr, width: 2),
          ),
        ),
        child: Center(
          child: Text(
            AppLocalizations.of(context).tripPatchHere,
            textScaler: TextScaler.noScaling,
            style: TypeTokens.caption.copyWith(
              color: tokens.hibr,
              fontWeight: FontWeight.w700,
              fontVariations: const [FontVariation('wght', 700)],
              height: 1,
            ),
          ),
        ),
      ),
    );
    return TripPulse(amplitude: 0.18, child: star);
  }
}

class StationPatch extends StatelessWidget {
  const StationPatch({required this.slot, required this.pulse, super.key});

  final int slot;
  final bool pulse;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final station = tokens.stations[slot % tokens.stations.length];
    final patch = SizedBox.square(
      dimension: patchSize,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: station.fill,
          shape: BoxShape.circle,
          border: Border.all(
            color: pulse ? tokens.danger : tokens.hibr,
            width: pulse ? 3 : 2,
          ),
        ),
        child: Center(
          child: Text(
            AppLocalizations.of(context).stationLetter(slot),
            textScaler: TextScaler.noScaling,
            style: TypeTokens.caption.copyWith(
              color: station.letter,
              fontWeight: FontWeight.w700,
              fontVariations: const [FontVariation('wght', 700)],
              height: 1,
            ),
          ),
        ),
      ),
    );
    if (!pulse) return patch;
    return TripPulse(amplitude: 0.18, child: patch);
  }
}
