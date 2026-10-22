// The payment dispute (ux-spec «خناقة على الدفع», FR-031, FR-032): the clock
// stops on a card that asks «مين اللي دفع؟» between the two passengers'
// faces, placed as they sit, each with their seat and under what they
// said. A tap on a face says that one paid.
import 'package:content_models/content_models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/app_theme.dart';
import 'package:wassal/core/theme/tokens/shape.dart';
import 'package:wassal/core/theme/tokens/space.dart';
import 'package:wassal/core/theme/tokens/typography.dart';
import 'package:wassal/features/trip/domain/skin_looks.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';
import 'package:wassal/features/trip/presentation/cards/trip_card.dart';
import 'package:wassal/features/trip/presentation/overlays/bubbles_layer.dart';
import 'package:wassal/features/trip/presentation/scene/passenger_art.dart';
import 'package:wassal/features/trip/presentation/trip_scope.dart';
import 'package:wassal/features/trip/presentation/trip_text.dart';
import 'package:wassal/features/trip/trip_providers.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

/// A face on the card: a near-row face, at the scene's face proportions.
const _portraitWidth = 88.0;
const _portraitHeight = 101.0;

/// One of the two, where they sit, and what they are saying.
typedef _Side = ({PassengerView passenger, Seat? seat, String? said});

class DisputeCard extends StatelessWidget {
  const DisputeCard({super.key});

  static Key faceKey(String passengerId) =>
      ValueKey('trip-dispute-$passengerId');

  @override
  Widget build(BuildContext context) {
    final seats = {
      for (final seat
          in TripScope.of(context).controller.session?.facts.definition.seats ??
              const <Seat>[])
        seat.seatId: seat,
    };
    return TripSelector<List<_Side>>(
      select: (model) {
        final view = model.view;
        final asked = view?.choices.whereType<DisputeChoice>().firstOrNull;
        if (view == null || asked == null) return const [];
        return [
          for (final id in [asked.a, asked.b])
            if (view.passenger(id) case final passenger?)
              (
                passenger: passenger,
                seat: seats[passenger.seatId],
                said: view.bubbles
                    .where((b) => b.passengerId == id)
                    .firstOrNull
                    ?.text,
              ),
        ]..sort(_byColumn);
      },
      equals: listEquals,
      builder: (context, sides) {
        if (sides.length != 2) return const SizedBox.shrink();
        return TripCard(
          title: AppLocalizations.of(context).tripDisputeTitle,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(child: _DisputeSide(side: sides[0])),
                const SizedBox(width: SpaceTokens.m),
                Expanded(child: _DisputeSide(side: sides[1])),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// The cabin's right column first, as the row lays out right to left.
int _byColumn(_Side a, _Side b) =>
    (a.seat?.col.index ?? 0).compareTo(b.seat?.col.index ?? 0);

class _DisputeSide extends StatelessWidget {
  const _DisputeSide({required this.side});

  final _Side side;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = context.tokens;
    final passenger = side.passenger;
    final label = l10n.speaker(
      SpeakerLabel(labelKey: passenger.look.labelKey, slot: passenger.slot),
    );
    final seatName = switch (side.seat) {
      final seat? => l10n.seatName(seat.row, seat.col),
      null => null,
    };
    final controls = TripScope.of(context).controls;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (side.said case final said?)
          Padding(
            padding: const EdgeInsets.only(bottom: SpaceTokens.m),
            child: LayoutBuilder(
              builder: (context, constraints) => Bubble(
                text: said,
                style: BubbleStyle.fight,
                tailX: constraints.maxWidth / 2,
                tailDown: true,
              ),
            ),
          ),
        Shakeable(
          controlKey: TripControls.disputeKey(passenger.passengerId),
          child: Semantics(
            button: true,
            label: l10n.tripDisputePaid(
              seatName == null ? label : l10n.tripDisputeSide(label, seatName),
            ),
            excludeSemantics: true,
            child: GestureDetector(
              key: DisputeCard.faceKey(passenger.passengerId),
              behavior: HitTestBehavior.opaque,
              onTap: () => controls.answerDispute(passenger.passengerId),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: tokens.waraq,
                  border: Border.all(
                    color: tokens.hibr,
                    width: ShapeTokens.borderCard,
                  ),
                  borderRadius: BorderRadius.circular(
                    ShapeTokens.radiusControl,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: tokens.hibr,
                      offset: const Offset(0, ShapeTokens.shadowCard),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(SpaceTokens.s),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: _portraitWidth,
                        height: _portraitHeight,
                        child: PassengerPortrait(passenger: passenger),
                      ),
                      const SizedBox(height: SpaceTokens.xs),
                      Text(
                        label,
                        textAlign: TextAlign.center,
                        style: TypeTokens.label.copyWith(color: tokens.hibr),
                      ),
                      if (seatName != null)
                        Text(
                          seatName,
                          textAlign: TextAlign.center,
                          style: TypeTokens.caption.copyWith(
                            color: tokens.hibr,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A passenger's face outside the scene, drawn by the same art as in it.
class PassengerPortrait extends ConsumerStatefulWidget {
  const PassengerPortrait({required this.passenger, super.key});

  final PassengerView passenger;

  @override
  ConsumerState<PassengerPortrait> createState() => _PassengerPortraitState();
}

class _PassengerPortraitState extends ConsumerState<PassengerPortrait> {
  /// Past the character's blend into its pose.
  static const _settle = 0.25;

  PassengerArt? _art;
  SkinLook? _look;
  WassalTokens? _tokens;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(PassengerPortrait oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.passenger != widget.passenger) _sync();
  }

  void _sync() {
    final tokens = context.tokens;
    final look = widget.passenger.look;
    if (_art == null || look != _look || tokens != _tokens) {
      _art?.dispose();
      _art = ref.read(passengerArtProvider).create(look, tokens);
      _look = look;
      _tokens = tokens;
    }
    _art!
      ..update(widget.passenger)
      ..advance(_settle);
  }

  @override
  void dispose() {
    _art?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _PortraitPainter(_art!, widget.passenger));
}

class _PortraitPainter extends CustomPainter {
  _PortraitPainter(this.art, this.passenger);

  final PassengerArt art;

  /// What [art] shows, so a change repaints.
  final PassengerView passenger;

  @override
  void paint(Canvas canvas, Size size) =>
      art.render(canvas, Offset.zero & size);

  @override
  bool shouldRepaint(_PortraitPainter oldDelegate) =>
      oldDelegate.art != art || oldDelegate.passenger != passenger;
}
