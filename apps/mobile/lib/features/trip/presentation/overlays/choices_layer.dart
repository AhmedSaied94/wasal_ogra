// The answers next to a passenger (layer 7, HANDOFF `TripEvents` block 6,
// FR-031): a `ChoicePopover` under their face while the trip runs, a
// claim's «ماشي» and «لأ، ما دفعتش!», or a change request's note held out
// with «فكّله» and «معلش». Each popover stays inside the scene, clear of the
// dashboard's overlap and of the others. Also the ledger's `LedgerBadge`,
// which the patches layer draws in place of a tag.
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/theme/components/pressable.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/trip/domain/scene_layout.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';
import 'package:wassal/features/trip/presentation/overlays/token_layer.dart';
import 'package:wassal/features/trip/presentation/trip_scope.dart';
import 'package:wassal/features/trip/presentation/trip_text.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

/// Space between a popover and the tag above it, or another popover.
const _gap = SpaceTokens.s2;

/// A popover keeps this far from the scene's edges.
const _margin = SpaceTokens.s10;

/// A question being asked: a claim, or a change request for [note], by the
/// one wearing [lookKey].
typedef _Asked = ({
  String passengerId,
  String seatId,
  String lookKey,
  int? note,
});

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
        return [
          for (final choice in view.choices)
            if (_askedOf(choice) case (final passengerId, final note))
              if (view.passenger(passengerId) case final p?)
                (
                  passengerId: passengerId,
                  seatId: p.seatId,
                  lookKey: p.look.labelKey,
                  note: note,
                ),
        ];
      },
      equals: listEquals,
      builder: (context, asked) {
        final placed = [
          for (final a in asked)
            if (layout.seats[a.seatId] case final seat?) (a, _anchorOf(seat)),
        ];
        return CustomMultiChildLayout(
          delegate: _UnderFaces([for (final (_, at) in placed) at]),
          children: [
            for (final (i, (a, _)) in placed.indexed)
              LayoutId(
                id: i,
                child: switch (a.note) {
                  null => _ClaimAnswers(
                    key: rowKey(a.passengerId),
                    passengerId: a.passengerId,
                    lookKey: a.lookKey,
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

/// Where a popover hangs: under the face's middle, below the face and its
/// tag (`TripEvents`: the effendi's popover starts where his tag ends).
Offset _anchorOf(SeatLayout seat) {
  final head = seat.head;
  return Offset(
    head.left + head.width / 2,
    math.max(head.top + head.height, seat.tag.y + seat.tagSize / 2),
  );
}

/// Puts popover `i` centred under `anchors[i]`, inside the scene and above
/// the dashboard's overlap; one that would cover an earlier one moves above
/// it, or below when there is no room above.
class _UnderFaces extends MultiChildLayoutDelegate {
  _UnderFaces(this.anchors);

  final List<Offset> anchors;

  @override
  void performLayout(Size size) {
    final bottom = size.height - dashboardOverlap - _gap;
    final placed = <Rect>[];
    for (var i = 0; i < anchors.length; i++) {
      final anchor = anchors[i];
      final row = layoutChild(
        i,
        BoxConstraints.loose(Size(size.width - 2 * _margin, size.height)),
      );
      final left = (anchor.dx - row.width / 2)
          .clamp(_margin, math.max(_margin, size.width - _margin - row.width))
          .toDouble();
      var top = math.min(anchor.dy + _gap, bottom - row.height);
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
      !listEquals(anchors, oldDelegate.anchors);
}

class _ClaimAnswers extends StatelessWidget {
  const _ClaimAnswers({
    required this.passengerId,
    required this.lookKey,
    super.key,
  });

  final String passengerId;
  final String lookKey;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controls = TripScope.of(context).controls;
    return Shakeable(
      controlKey: TripControls.claimKey(passengerId),
      child: ChoicePopover(
        semanticLabel: l10n.tripClaimAsks(l10n.lookLabel(lookKey)),
        children: [
          ChoiceButton(
            key: ChoicesLayer.claimKey(passengerId, insist: false),
            label: l10n.tripClaimAccept,
            onTap: () => controls.answerClaim(passengerId, insist: false),
          ),
          ChoiceButton(
            key: ChoicesLayer.claimKey(passengerId, insist: true),
            label: l10n.tripClaimInsist,
            danger: true,
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
      child: ChoicePopover(
        children: [
          // The note they hold out.
          ExcludeSemantics(
            child: Center(
              widthFactor: 1,
              heightFactor: 1,
              child: Consumer(
                builder: (context, ref, _) => MoneyNote(
                  kind: MoneyNoteKind.fare,
                  amount: ref
                      .watch(numberFormatterProvider)
                      .piasters(notePiasters),
                ),
              ),
            ),
          ),
          ChoiceButton(
            key: ChoicesLayer.changeRequestKey(passengerId, agree: true),
            label: l10n.tripChangeRequestAgree,
            onTap: () => controls.answerChangeRequest(passengerId, agree: true),
          ),
          ChoiceButton(
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

/// A white popover beside a passenger (`TripEvents` block 6): radius 18,
/// padding 5, its buttons 6 apart, on the `popover` lip.
class ChoicePopover extends StatelessWidget {
  const ChoicePopover({required this.children, this.semanticLabel, super.key});

  final List<Widget> children;

  /// What the group asks, read before its buttons.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: semanticLabel,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: ColorTokens.paper,
          borderRadius: BorderRadius.all(
            Radius.circular(DesignExtras.popoverRadius),
          ),
          boxShadow: [LipTokens.popover],
        ),
        child: Padding(
          padding: const EdgeInsets.all(DesignExtras.popoverPadding),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: SpaceTokens.s6,
            children: children,
          ),
        ),
      ),
    );
  }
}

/// A popover's answer: 44 high, radius 14, 15/700 ink on `ground`, or on
/// `danger` with its 3 pt lip.
class ChoiceButton extends StatelessWidget {
  const ChoiceButton({
    required this.label,
    required this.onTap,
    this.danger = false,
    super.key,
  });

  final String label;
  final VoidCallback onTap;
  final bool danger;

  static const _corners = BorderRadius.all(
    Radius.circular(DesignExtras.choiceRadius),
  );

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      haptic: false,
      semanticLabel: label,
      lip: danger ? DesignExtras.choiceDangerLip : null,
      borderRadius: _corners,
      child: Container(
        height: LayoutTokens.touchMin,
        constraints: const BoxConstraints(minWidth: LayoutTokens.touchMin),
        padding: const EdgeInsets.symmetric(horizontal: SpaceTokens.s16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: danger ? ColorTokens.danger : ColorTokens.ground,
          borderRadius: _corners,
        ),
        child: Text(
          label,
          maxLines: 1,
          style: DesignExtras.choiceLabel.copyWith(color: ColorTokens.ink),
        ),
      ),
    );
  }
}

/// The ledger's word over a passenger (`TripEvents` block 5): an 18 pt
/// pill at 12/700, «دافع» `primary`/white, «لسه» `danger`/ink, «على
/// صاحبه» white/ink.
class LedgerBadgeChip extends StatelessWidget {
  const LedgerBadgeChip({required this.badge, super.key});

  final LedgerBadge badge;

  static Key badgeKey(String passengerId) =>
      ValueKey('trip-ledger-$passengerId');

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final (fill, ink) = switch (badge) {
      LedgerBadge.paid => (ColorTokens.primary, ColorTokens.paper),
      LedgerBadge.unpaid => (ColorTokens.danger, ColorTokens.ink),
      LedgerBadge.onFriend => (ColorTokens.paper, ColorTokens.ink),
    };
    return Container(
      height: DesignExtras.ledgerBadgeHeight,
      padding: const EdgeInsets.symmetric(horizontal: SpaceTokens.s8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: const BorderRadius.all(
          Radius.circular(RadiusTokens.pill),
        ),
      ),
      child: Text(
        l10n.ledgerWord(badge),
        maxLines: 1,
        style: TypeTokens.label.weight(700).copyWith(color: ink, height: 1),
      ),
    );
  }
}
