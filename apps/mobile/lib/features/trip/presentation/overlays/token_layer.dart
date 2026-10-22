// Money in transit (layer 5): Flutter chips over the scene, moved every
// frame by a `Flow` from the view and the clock's alpha (research R3), so the
// amounts get the app's fonts, the digit setting and text scaling. Notes a
// bump knocked to the floor lie where they fell until a tap picks them up.
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/theme/app_theme.dart';
import 'package:wassal/core/theme/tokens/shape.dart';
import 'package:wassal/core/theme/tokens/space.dart';
import 'package:wassal/core/theme/tokens/typography.dart';
import 'package:wassal/features/trip/application/trip_controller.dart';
import 'package:wassal/features/trip/domain/scene_layout.dart';
import 'package:wassal/features/trip/domain/step_accumulator.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';
import 'package:wassal/features/trip/presentation/trip_scope.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

/// A token's minimum size (ux-spec minimum sizes).
const tokenMinWidth = 40.0;
const tokenMinHeight = 24.0;

typedef _Face = ({int id, TokenTint kind, int amount, bool blocked});

class TokenLayer extends StatelessWidget {
  const TokenLayer({required this.layout, super.key});

  final SceneLayout layout;

  @override
  Widget build(BuildContext context) {
    final scope = TripScope.of(context);
    return ExcludeSemantics(
      child: TripSelector<List<_Face>>(
        select: (model) => [
          for (final t in model.view?.tokens ?? const <TokenView>[])
            if (!t.dropped)
              (
                id: t.tokenId,
                kind: t.kind,
                amount: t.amountPiasters,
                blocked: t.blocked,
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
              TokenChip(
                key: ValueKey(f.id),
                kind: f.kind,
                amountPiasters: f.amount,
                blocked: f.blocked,
              ),
          ],
        ),
      ),
    );
  }
}

/// Where a token is drawn at this frame.
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
    from.y + (to.y - from.y) * progress,
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

/// A note in transit: green on its way to the driver, blue on its way back,
/// orange with «؟» when held up.
class TokenChip extends ConsumerWidget {
  const TokenChip({
    required this.kind,
    required this.amountPiasters,
    required this.blocked,
    super.key,
  });

  final TokenTint kind;
  final int amountPiasters;
  final bool blocked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final amount = ref.watch(numberFormatterProvider).piasters(amountPiasters);
    final (fill, ink) = blocked
        ? (tokens.danger, tokens.hibr)
        : switch (kind) {
            TokenTint.fare => (tokens.fare, tokens.hibr),
            TokenTint.change => (tokens.primary, tokens.waraq),
          };
    return ConstrainedBox(
      constraints: const BoxConstraints(
        minWidth: tokenMinWidth,
        minHeight: tokenMinHeight,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: fill,
          border: Border.all(color: tokens.hibr, width: 2),
          borderRadius: BorderRadius.circular(ShapeTokens.radiusControl),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          child: Center(
            widthFactor: 1,
            heightFactor: 1,
            child: Text(
              blocked
                  ? AppLocalizations.of(context).tripTokenBlocked(amount)
                  : amount,
              maxLines: 1,
              style: TypeTokens.body.copyWith(
                color: ink,
                fontWeight: FontWeight.w700,
                fontVariations: const [FontVariation('wght', 700)],
                height: 1.2,
              ),
            ),
          ),
        ),
      ),
    );
  }
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

  /// Centered where the note lies.
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
    final tokens = context.tokens;
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
            minWidth: ShapeTokens.minTouch,
            minHeight: ShapeTokens.minTouch,
          ),
          child: Center(
            widthFactor: 1,
            heightFactor: 1,
            child: Shakeable(
              controlKey: TripControls.droppedKey(tokenId),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minWidth: tokenMinWidth,
                  minHeight: tokenMinHeight,
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: tokens.waraq,
                    border: Border.all(color: tokens.hibr, width: 2),
                    borderRadius: BorderRadius.circular(
                      ShapeTokens.radiusControl,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: SpaceTokens.xs,
                      vertical: 1,
                    ),
                    child: Center(
                      widthFactor: 1,
                      heightFactor: 1,
                      child: Text(
                        amount,
                        maxLines: 1,
                        style: TypeTokens.body.copyWith(
                          color: tokens.hibr,
                          fontWeight: FontWeight.w700,
                          fontVariations: const [FontVariation('wght', 700)],
                          height: 1.2,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
