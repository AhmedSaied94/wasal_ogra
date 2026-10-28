// The passengers' tap and drop areas (layer 6): `SeatLayout.hit`,
// transparent, at least 44×44, never overlapping, each a button for screen
// readers that names the look, the seat and the stop, and «ليه باقي» while
// their stop is next and they're owed (spec FR-036, M02 FR-033).
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

typedef _Seated = ({
  String id,
  String seatId,
  String labelKey,
  int? slot,
  String? stopName,
  bool owed,
  LedgerBadge? ledger,
});

class HitAreas extends StatelessWidget {
  const HitAreas({required this.layout, super.key});

  final SceneLayout layout;

  static Key keyOf(String passengerId) =>
      ValueKey('trip-passenger-$passengerId');

  @override
  Widget build(BuildContext context) {
    return TripSelector<List<_Seated>>(
      select: (model) {
        final view = model.view;
        return [
          for (final p in model.view?.passengers ?? const <PassengerView>[])
            if (p.presence == PresenceView.aboard ||
                p.presence == PresenceView.boarding)
              (
                id: p.passengerId,
                seatId: p.seatId,
                labelKey: p.look.labelKey,
                slot: p.slot,
                stopName: view == null ? null : stopNameOf(view, p.slot),
                owed: p.nearStopPulse,
                ledger: p.ledgerBadge,
              ),
        ];
      },
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
                  label: labelOf(
                    AppLocalizations.of(context),
                    seat,
                    lookKey: p.labelKey,
                    slot: p.slot,
                    stopName: p.stopName,
                    owed: p.owed,
                    ledger: p.ledger,
                  ),
                ),
              ),
        ],
      ),
    );
  }

  /// A passenger's label (the coach's target says the same). While the
  /// ledger is open, its word ends it (`TripEvents` accessibility).
  static String labelOf(
    AppLocalizations l10n,
    SeatLayout seat, {
    required String lookKey,
    required int? slot,
    required String? stopName,
    required bool owed,
    required LedgerBadge? ledger,
  }) {
    final label = l10n.passengerLabel(
      lookKey: lookKey,
      row: seat.row,
      col: seat.col,
      slot: slot,
      stopName: stopName,
      owed: owed,
    );
    return switch (ledger) {
      final badge? => l10n.pairLabel(label, l10n.ledgerWord(badge)),
      null => label,
    };
  }
}

/// The name of the stop of [slot] on the strip.
String? stopNameOf(TripView view, int? slot) =>
    view.strip.chips.where((c) => c.slot == slot).firstOrNull?.name;

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
