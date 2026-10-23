// The answers next to a passenger (layer 7, FR-031), under their face while
// the trip runs: a claim's «ماشي» and «لأ، ما دفعتش!», and a change
// request's note held out with «فكّله» and «معلش». Each row stays inside
// the scene, clear of the dashboard's overlap and of the other rows. While
// the ledger is open, each face wears «دافع» or «لسه».
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/app_theme.dart';
import 'package:wassal/core/theme/tokens/shape.dart';
import 'package:wassal/core/theme/tokens/space.dart';
import 'package:wassal/core/theme/tokens/typography.dart';
import 'package:wassal/features/trip/domain/scene_layout.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';
import 'package:wassal/features/trip/presentation/overlays/token_layer.dart';
import 'package:wassal/features/trip/presentation/trip_scope.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

/// Space between a row and the face, an edge or another row.
const _gap = SpaceTokens.xs;

/// A row keeps this far from the scene's edges.
const _margin = SpaceTokens.s;

/// A question being asked: a claim, or a change request for [note].
typedef _Asked = ({String passengerId, String seatId, int? note});

class ChoicesLayer extends StatelessWidget {
  const ChoicesLayer({required this.layout, super.key});

  final SceneLayout layout;

  static Key rowKey(String passengerId) =>
      ValueKey('trip-choices-$passengerId');

  static Key claimKey(String passengerId, {required bool insist}) =>
      ValueKey('trip-claim-$passengerId-${insist ? 'insist' : 'accept'}');

  static Key changeRequestRowKey(String passengerId) =>
      ValueKey('trip-change-request-$passengerId');

  static Key changeRequestKey(String passengerId, {required bool agree}) =>
      ValueKey(
        'trip-change-request-$passengerId-${agree ? 'agree' : 'decline'}',
      );

  @override
  Widget build(BuildContext context) {
    return TripSelector<List<_Asked>>(
      select: (model) {
        final view = model.view;
        if (view == null) return const [];
        final seats = {
          for (final p in view.passengers) p.passengerId: p.seatId,
        };
        return [
          for (final choice in view.choices)
            if (_askedOf(choice) case (final passengerId, final note))
              if (seats[passengerId] case final seatId?)
                (passengerId: passengerId, seatId: seatId, note: note),
        ];
      },
      equals: listEquals,
      builder: (context, asked) {
        final placed = [
          for (final a in asked)
            if (layout.seats[a.seatId] case final seat?) (a, seat.face),
        ];
        return CustomMultiChildLayout(
          delegate: _UnderFaces([for (final (_, face) in placed) face]),
          children: [
            for (final (i, (a, _)) in placed.indexed)
              LayoutId(
                id: i,
                child: switch (a.note) {
                  null => _ClaimAnswers(
                    key: rowKey(a.passengerId),
                    passengerId: a.passengerId,
                  ),
                  final note => _ChangeRequestAnswers(
                    key: changeRequestRowKey(a.passengerId),
                    passengerId: a.passengerId,
                    notePiasters: note,
                  ),
                },
              ),
          ],
        );
      },
    );
  }
}

/// Who [choice] asks next to their face, and the note a change request
/// holds out; null for the dispute, which has its own card.
(String, int?)? _askedOf(ChoiceView choice) => switch (choice) {
  ClaimChoice(:final passengerId) => (passengerId, null),
  ChangeRequestChoice(:final passengerId, :final notePiasters) => (
    passengerId,
    notePiasters,
  ),
  DisputeChoice() => null,
};

/// Puts row `i` under `faces[i]`, inside the scene and above the
/// dashboard's overlap; a row that would cover an earlier one moves above
/// it, or below when there is no room above.
class _UnderFaces extends MultiChildLayoutDelegate {
  _UnderFaces(this.faces);

  final List<math.Rectangle<double>> faces;

  @override
  void performLayout(Size size) {
    final bottom = size.height - dashboardOverlap - _gap;
    final placed = <Rect>[];
    for (var i = 0; i < faces.length; i++) {
      final face = faces[i];
      final row = layoutChild(
        i,
        BoxConstraints.loose(Size(size.width - 2 * _margin, size.height)),
      );
      final left = (face.left + face.width / 2 - row.width / 2)
          .clamp(_margin, math.max(_margin, size.width - _margin - row.width))
          .toDouble();
      var top = math.min(face.top + face.height + _gap, bottom - row.height);
      var rect = Offset(left, top) & row;
      for (final other in placed) {
        if (!rect.overlaps(other.inflate(_gap / 2))) continue;
        top = other.top - _gap - row.height;
        if (top < _margin) top = other.bottom + _gap;
        rect = Offset(left, top) & row;
      }
      placed.add(rect);
      positionChild(i, rect.topLeft);
    }
  }

  @override
  bool shouldRelayout(_UnderFaces oldDelegate) =>
      !listEquals(faces, oldDelegate.faces);
}

class _ClaimAnswers extends StatelessWidget {
  const _ClaimAnswers({required this.passengerId, super.key});

  final String passengerId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controls = TripScope.of(context).controls;
    return Shakeable(
      controlKey: TripControls.claimKey(passengerId),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Answer(
            key: ChoicesLayer.claimKey(passengerId, insist: false),
            label: l10n.tripClaimAccept,
            onTap: () => controls.answerClaim(passengerId, insist: false),
          ),
          const SizedBox(width: SpaceTokens.s),
          _Answer(
            key: ChoicesLayer.claimKey(passengerId, insist: true),
            label: l10n.tripClaimInsist,
            onTap: () => controls.answerClaim(passengerId, insist: true),
          ),
        ],
      ),
    );
  }
}

class _ChangeRequestAnswers extends StatelessWidget {
  const _ChangeRequestAnswers({
    required this.passengerId,
    required this.notePiasters,
    super.key,
  });

  final String passengerId;
  final int notePiasters;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controls = TripScope.of(context).controls;
    return Shakeable(
      controlKey: TripControls.changeRequestKey(passengerId),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The note they hold out.
          ExcludeSemantics(
            child: TokenChip(
              kind: TokenTint.fare,
              amountPiasters: notePiasters,
              blocked: false,
            ),
          ),
          const SizedBox(width: SpaceTokens.s),
          _Answer(
            key: ChoicesLayer.changeRequestKey(passengerId, agree: true),
            label: l10n.tripChangeRequestAgree,
            onTap: () => controls.answerChangeRequest(passengerId, agree: true),
          ),
          const SizedBox(width: SpaceTokens.s),
          _Answer(
            key: ChoicesLayer.changeRequestKey(passengerId, agree: false),
            label: l10n.tripChangeRequestDecline,
            onTap: () =>
                controls.answerChangeRequest(passengerId, agree: false),
          ),
        ],
      ),
    );
  }
}

class _Answer extends StatelessWidget {
  const _Answer({required this.label, required this.onTap, super.key});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: ShapeTokens.minTouch,
            minHeight: ShapeTokens.minTouch,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: tokens.waraq,
              border: Border.all(
                color: tokens.hibr,
                width: ShapeTokens.borderCard,
              ),
              borderRadius: BorderRadius.circular(ShapeTokens.radiusControl),
              boxShadow: [
                BoxShadow(
                  color: tokens.hibr,
                  offset: const Offset(0, ShapeTokens.badgeOutline),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: SpaceTokens.m),
              child: Center(
                widthFactor: 1,
                heightFactor: 1,
                child: Text(
                  label,
                  style: TypeTokens.label.copyWith(color: tokens.hibr),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// While the ledger is open (`ledger_peek`), a badge on each face: «دافع»
/// or «لسه».
class LedgerBadgesLayer extends StatelessWidget {
  const LedgerBadgesLayer({required this.layout, super.key});

  final SceneLayout layout;

  @override
  Widget build(BuildContext context) {
    return TripSelector<List<(String, String, LedgerBadge)>>(
      select: (model) => [
        for (final p in model.view?.passengers ?? const <PassengerView>[])
          if (p.ledgerBadge case final badge?) (p.passengerId, p.seatId, badge),
      ],
      equals: listEquals,
      builder: (context, badges) => Stack(
        children: [
          for (final (passengerId, seatId, badge) in badges)
            if (layout.seats[seatId] case final seat?)
              Positioned(
                // Centered on the face, high on the head.
                left: seat.face.left + seat.face.width / 2,
                top: seat.face.top + seat.face.height * 0.12,
                child: FractionalTranslation(
                  translation: const Offset(-0.5, -0.5),
                  child: LedgerBadgeChip(
                    key: LedgerBadgeChip.badgeKey(passengerId),
                    paid: badge == LedgerBadge.paid,
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class LedgerBadgeChip extends StatelessWidget {
  const LedgerBadgeChip({required this.paid, super.key});

  final bool paid;

  static Key badgeKey(String passengerId) =>
      ValueKey('trip-ledger-$passengerId');

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: paid ? tokens.bubbleThanks : tokens.danger,
        border: Border.all(color: tokens.hibr, width: 2),
        borderRadius: BorderRadius.circular(ShapeTokens.radiusControl),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: SpaceTokens.s,
          vertical: 2,
        ),
        child: Text(
          paid ? l10n.tripLedgerPaid : l10n.tripLedgerUnpaid,
          style: TypeTokens.caption.copyWith(
            color: tokens.hibr,
            fontWeight: FontWeight.w700,
            fontVariations: const [FontVariation('wght', 700)],
          ),
        ),
      ),
    );
  }
}
