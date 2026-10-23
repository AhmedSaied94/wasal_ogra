// The payment dispute (ux-spec «خناقة على الدفع», FR-031, FR-032): the clock
// stops on a card that asks «مين اللي دفع؟» between the two passengers'
// faces, placed as they sit, each with their seat and under what they
// said. A tap on a face says that one paid.
import 'package:content_models/content_models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/components/pressable.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/trip/domain/looks.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';
import 'package:wassal/features/trip/presentation/cards/trip_card.dart';
import 'package:wassal/features/trip/presentation/overlays/bubbles_layer.dart';
import 'package:wassal/features/trip/presentation/scene/passenger_art.dart';
import 'package:wassal/features/trip/presentation/trip_scope.dart';
import 'package:wassal/features/trip/presentation/trip_text.dart';
import 'package:wassal/features/trip/trip_providers.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

/// A face on the card (`Components` «مين اللي دفع؟»): a 56 pt `ground`
/// tile, radius 16, with the passenger drawn in it at the scene's
/// proportions.
const _faceSize = 56.0;
const _faceRadius = 16.0;
const _portraitHeight = 52.0;
const _portraitWidth = _portraitHeight * 88 / 101;

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
                const SizedBox(width: SpaceTokens.s12),
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
    final passenger = side.passenger;
    final label = l10n.speaker(
      SpeakerLabel(labelKey: passenger.look.labelKey, slot: passenger.slot),
    );
    final seatName = switch (side.seat) {
      final seat? => l10n.seatName(seat.row, seat.col),
      null => null,
    };
    final controls = TripScope.of(context).controls;
    final caption = TypeTokens.label.copyWith(color: ColorTokens.ink);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (side.said case final said?)
          Padding(
            padding: const EdgeInsets.only(bottom: SpaceTokens.s12),
            child: SpeechBubble(text: said, variant: SpeechBubbleVariant.fight),
          ),
        Shakeable(
          controlKey: TripControls.disputeKey(passenger.passengerId),
          child: Pressable(
            key: DisputeCard.faceKey(passenger.passengerId),
            onTap: () => controls.answerDispute(passenger.passengerId),
            haptic: false,
            semanticLabel: l10n.tripDisputePaid(
              seatName == null ? label : l10n.tripDisputeSide(label, seatName),
            ),
            borderRadius: const BorderRadius.all(Radius.circular(_faceRadius)),
            child: SizedBox.square(
              dimension: _faceSize,
              // The art runs past its box (the shoulders); the tile cuts it.
              child: ClipRRect(
                borderRadius: const BorderRadius.all(
                  Radius.circular(_faceRadius),
                ),
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    color: ColorTokens.ground,
                    borderRadius: BorderRadius.all(
                      Radius.circular(_faceRadius),
                    ),
                  ),
                  child: Center(
                    child: SizedBox(
                      width: _portraitWidth,
                      height: _portraitHeight,
                      child: PassengerPortrait(passenger: passenger),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: SpaceTokens.s6),
        Text(label, textAlign: TextAlign.center, style: caption.weight(700)),
        if (seatName != null)
          Text(seatName, textAlign: TextAlign.center, style: caption),
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
  Look? _look;

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
    final look = widget.passenger.look;
    if (_art == null || look != _look) {
      _art?.dispose();
      _art = ref.read(passengerArtProvider).create(look);
      _look = look;
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
