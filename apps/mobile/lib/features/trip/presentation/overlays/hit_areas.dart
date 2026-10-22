// The passengers' tap and drop areas (layer 6): transparent, at least 44×44,
// never overlapping, each a button for screen readers that names the look,
// the seat and the station letter, and nothing about payment (FR-033).
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/features/trip/domain/scene_layout.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';
import 'package:wassal/features/trip/presentation/trip_scope.dart';
import 'package:wassal/features/trip/presentation/trip_text.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

/// What a drag from the hand carries.
@immutable
final class HandDrag {
  const HandDrag();
}

typedef _Seated = ({String id, String seatId, String labelKey, int? slot});

class HitAreas extends StatelessWidget {
  const HitAreas({required this.layout, super.key});

  final SceneLayout layout;

  static Key keyOf(String passengerId) =>
      ValueKey('trip-passenger-$passengerId');

  @override
  Widget build(BuildContext context) {
    return TripSelector<List<_Seated>>(
      select: (model) => [
        for (final p in model.view?.passengers ?? const <PassengerView>[])
          if (p.presence == PresenceView.aboard ||
              p.presence == PresenceView.boarding)
            (
              id: p.passengerId,
              seatId: p.seatId,
              labelKey: p.look.labelKey,
              slot: p.slot,
            ),
      ],
      equals: listEquals,
      builder: (context, seated) => Stack(
        children: [
          for (final p in seated)
            if (layout.seats[p.seatId] case final seat?)
              Positioned(
                left: seat.hit.left,
                top: seat.hit.top,
                width: seat.hit.width,
                height: seat.hit.height,
                child: _PassengerHit(
                  passengerId: p.id,
                  label: _label(AppLocalizations.of(context), p, seat),
                ),
              ),
        ],
      ),
    );
  }

  String _label(AppLocalizations l10n, _Seated p, SeatGeometry seat) {
    final look = l10n.lookLabel(p.labelKey);
    final where = l10n.seatName(seat.row, seat.col);
    return switch (p.slot) {
      final slot? => l10n.tripSemanticsPassenger(
        look,
        where,
        l10n.stationLetter(slot),
      ),
      null => l10n.tripSemanticsPassengerNoStation(look, where),
    };
  }
}

class _PassengerHit extends StatelessWidget {
  const _PassengerHit({required this.passengerId, required this.label});

  final String passengerId;
  final String label;

  @override
  Widget build(BuildContext context) {
    final controls = TripScope.of(context).controls;
    return DragTarget<HandDrag>(
      onAcceptWithDetails: (_) => controls.dropOn(passengerId),
      builder: (context, candidates, _) => Semantics(
        key: HitAreas.keyOf(passengerId),
        container: true,
        button: true,
        label: label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => controls.tapPassenger(passengerId),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}
