// Money in the scene (layer 5, HANDOFF §3.4 `MoneyNote`): Flutter notes over
// the scene, moved every frame by a `Flow` from the view and the clock's
// alpha along the hop on a slight arc (M02 research R3), so the amounts get
// the app's fonts, the digit setting and text scaling. The player's hand
// shows as the `inHand` note at the driver's palm; notes a bump knocked to
// the floor lie where they fell, ringed, until a tap picks them up.
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/trip/application/trip_controller.dart';
import 'package:wassal/features/trip/domain/scene_layout.dart';
import 'package:wassal/features/trip/domain/step_accumulator.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';
import 'package:wassal/features/trip/presentation/trip_colors.dart';
import 'package:wassal/features/trip/presentation/trip_scope.dart';
import 'package:wassal/features/trip/presentation/trip_text.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

/// A token's minimum size (ux-spec minimum sizes); a note is 42×26.
const tokenMinWidth = 40.0;
const tokenMinHeight = 24.0;

/// A hop rises this far at its middle.
const _arc = 10.0;

enum MoneyNoteKind { fare, change, blocked, fallen, inHand }

/// A note: h 26, at least 42 wide, its digits 16/700 in its kind's colours
/// with a 3 pt lip; a blocked one wears «؟», a fallen one a `sun.glow` ring.
class MoneyNote extends StatelessWidget {
  const MoneyNote({required this.kind, required this.amount, super.key});

  final MoneyNoteKind kind;
  final String amount;

  static const bodyKey = ValueKey('money-note-body');

  NoteColors get _colors => switch (kind) {
    MoneyNoteKind.fare || MoneyNoteKind.fallen => TripColors.fare,
    MoneyNoteKind.change => TripColors.change,
    MoneyNoteKind.blocked => TripColors.blocked,
    MoneyNoteKind.inHand => TripColors.inHand,
  };

  @override
  Widget build(BuildContext context) {
    final colors = _colors;
    final body = Container(
      key: bodyKey,
      height: DesignExtras.noteMin.height,
      constraints: BoxConstraints(minWidth: DesignExtras.noteMin.width),
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: colors.bg,
        borderRadius: const BorderRadius.all(
          Radius.circular(DesignExtras.noteRadius),
        ),
        boxShadow: [
          if (kind == MoneyNoteKind.fallen)
            DesignExtras.fallenRing.spread
          else
            DesignExtras.noteLip(colors.lip),
        ],
      ),
      // Centred, without growing: an aligned Container fills a loose width.
      child: Center(
        widthFactor: 1,
        child: Text(
          amount,
          maxLines: 1,
          softWrap: false,
          textScaler: TripTextScale.clamp(context),
          style: DesignExtras.pillNumber.copyWith(color: colors.text),
        ),
      ),
    );
    final note = kind == MoneyNoteKind.blocked
        ? Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              body,
              Positioned(
                top: -DesignExtras.noteBadgeRise,
                child: Container(
                  width: DesignExtras.noteBadge,
                  height: DesignExtras.noteBadge,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: ColorTokens.danger,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    AppLocalizations.of(context).tripNoteBlockedMark,
                    textScaler: TripTextScale.clamp(context),
                    style: TypeTokens.body
                        .weight(700)
                        .copyWith(color: ColorTokens.ink, height: 1),
                  ),
                ),
              ),
            ],
          )
        : body;
    return switch (kind) {
      MoneyNoteKind.inHand => Transform.rotate(
        angle: DesignExtras.inHandTilt,
        child: note,
      ),
      MoneyNoteKind.fallen => Transform.rotate(
        angle: DesignExtras.fallenTilt,
        child: note,
      ),
      _ => note,
    };
  }
}

typedef _Face = ({int id, MoneyNoteKind kind, int amount});

class TokenLayer extends ConsumerWidget {
  const TokenLayer({required this.layout, super.key});

  final SceneLayout layout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = TripScope.of(context);
    final numbers = ref.watch(numberFormatterProvider);
    return ExcludeSemantics(
      child: Stack(
        children: [
          Positioned.fill(
            child: TripSelector<List<_Face>>(
              select: (model) => [
                for (final t in model.view?.tokens ?? const <TokenView>[])
                  if (!t.dropped)
                    (
                      id: t.tokenId,
                      kind: t.blocked
                          ? MoneyNoteKind.blocked
                          : switch (t.kind) {
                              TokenTint.fare => MoneyNoteKind.fare,
                              TokenTint.change => MoneyNoteKind.change,
                            },
                      amount: t.amountPiasters,
                    ),
              ],
              equals: listEquals,
              builder: (context, faces) => Flow(
                delegate: _TokenFlow(
                  controller: scope.controller,
                  layout: layout,
                  ids: [for (final f in faces) f.id],
                ),
                children: [
                  for (final f in faces)
                    MoneyNote(
                      key: ValueKey(f.id),
                      kind: f.kind,
                      amount: numbers.piasters(f.amount),
                    ),
                ],
              ),
            ),
          ),
          TripSelector<int>(
            select: (model) => model.view?.hand.totalPiasters ?? 0,
            builder: (context, total) {
              if (total == 0) return const SizedBox.shrink();
              final at =
                  Offset(layout.hand.x, layout.hand.y) +
                  DesignExtras.inHandFromPalm * layout.scale;
              return Positioned(
                left: at.dx,
                top: at.dy,
                child: FractionalTranslation(
                  translation: const Offset(-0.5, -0.5),
                  child: MoneyNote(
                    kind: MoneyNoteKind.inHand,
                    amount: numbers.piasters(total),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Where a token is drawn at this frame: along its hop, raised on an arc.
Offset tokenPosition(TokenView token, SceneLayout layout, double alpha) {
  final from = layout.anchorOf(token.from);
  final to = layout.anchorOf(token.to);
  if (token.atHolder || token.hopMs <= 0) return Offset(from.x, from.y);
  final progress = min(
    1,
    token.progressPermille / 1000 + alpha * engineStepMs / token.hopMs,
  );
  return Offset(
    from.x + (to.x - from.x) * progress,
    from.y + (to.y - from.y) * progress - sin(pi * progress) * _arc,
  );
}

class _TokenFlow extends FlowDelegate {
  _TokenFlow({
    required this.controller,
    required this.layout,
    required this.ids,
  }) : super(repaint: controller.frames);

  final TripController controller;
  final SceneLayout layout;
  final List<int> ids;

  @override
  BoxConstraints getConstraintsForChild(int i, BoxConstraints constraints) =>
      constraints.loosen();

  @override
  void paintChildren(FlowPaintingContext context) {
    final view = controller.view;
    if (view == null) return;
    final byId = {for (final t in view.tokens) t.tokenId: t};
    final alpha = view.phase == TripPhase.running ? controller.alpha : 0.0;
    for (final (i, id) in ids.indexed) {
      final token = byId[id];
      final size = context.getChildSize(i);
      if (token == null || size == null) continue;
      final at = tokenPosition(token, layout, alpha);
      context.paintChild(
        i,
        transform: Matrix4.translationValues(
          at.dx - size.width / 2,
          at.dy - size.height / 2,
          0,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(_TokenFlow oldDelegate) =>
      oldDelegate.layout != layout ||
      oldDelegate.controller != controller ||
      !listEquals(oldDelegate.ids, ids);
}

/// The notes on the floor, each a tap area of at least 44×44 over its
/// glint (FR-025, ux-spec «مطب»).
class DroppedLayer extends StatelessWidget {
  const DroppedLayer({required this.layout, super.key});

  final SceneLayout layout;

  static Key noteKey(int tokenId) => ValueKey('trip-dropped-$tokenId');

  @override
  Widget build(BuildContext context) {
    return TripSelector<List<DroppedMoneyView>>(
      select: (model) => model.view?.dropped ?? const [],
      equals: listEquals,
      builder: (context, dropped) =>
          Stack(children: [for (final note in dropped) _placed(note)]),
    );
  }

  /// Centred where the note lies.
  Widget _placed(DroppedMoneyView note) {
    final at = layout.floorAt(note.from, note.to, note.progressPermille);
    return Positioned(
      left: at.x,
      top: at.y,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -0.5),
        child: _DroppedNote(
          key: noteKey(note.tokenId),
          tokenId: note.tokenId,
          amountPiasters: note.amountPiasters,
        ),
      ),
    );
  }
}

class _DroppedNote extends ConsumerWidget {
  const _DroppedNote({
    required this.tokenId,
    required this.amountPiasters,
    super.key,
  });

  final int tokenId;
  final int amountPiasters;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final amount = ref.watch(numberFormatterProvider).piasters(amountPiasters);
    final controls = TripScope.of(context).controls;
    return Semantics(
      button: true,
      label: AppLocalizations.of(context).tripSemanticsDropped(amount),
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => controls.collect(tokenId),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: LayoutTokens.touchMin,
            minHeight: LayoutTokens.touchMin,
          ),
          child: Center(
            widthFactor: 1,
            heightFactor: 1,
            child: Shakeable(
              controlKey: TripControls.droppedKey(tokenId),
              child: MoneyNote(kind: MoneyNoteKind.fallen, amount: amount),
            ),
          ),
        ),
      ),
    );
  }
}
