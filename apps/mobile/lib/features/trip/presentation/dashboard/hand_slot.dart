// «في إيدك» (ux-spec «التابلوه» row 1): what the player holds, with the
// total at 20 pt. A tap returns it all to the drawer; a drag onto a
// passenger throws it, like a tap on them. Beside it, «رجّع» while a throw
// can be taken back, and the yellow «حد معاه فكة؟» with its breaks left.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/l10n/number_formatter.dart';
import 'package:wassal/core/theme/app_theme.dart';
import 'package:wassal/core/theme/tokens/shape.dart';
import 'package:wassal/core/theme/tokens/space.dart';
import 'package:wassal/core/theme/tokens/typography.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';
import 'package:wassal/features/trip/presentation/overlays/hit_areas.dart';
import 'package:wassal/features/trip/presentation/dashboard/tray.dart';
import 'package:wassal/features/trip/presentation/overlays/token_layer.dart';
import 'package:wassal/features/trip/presentation/trip_scope.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

/// The hand's total (ux-spec: 20 pt).
TextStyle get handTotalStyle => TypeTokens.button;

class HandSlot extends ConsumerWidget {
  const HandSlot({super.key});

  static const slotKey = ValueKey('trip-hand');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controls = TripScope.of(context).controls;
    final numbers = ref.watch(numberFormatterProvider);
    final l10n = AppLocalizations.of(context);
    return TripSelector<(HandView?, bool)>(
      select: (model) => (model.view?.hand, model.view?.breakMode ?? false),
      builder: (context, selected) {
        final (hand, breakMode) = selected;
        final empty = hand == null || hand.isEmpty;
        final total = numbers.piasters(hand?.totalPiasters ?? 0);
        final body = _HandBody(
          hand: hand,
          numbers: numbers,
          breakMode: breakMode,
        );
        final slot = Semantics(
          button: true,
          label: empty
              ? l10n.tripHandEmptySemantics
              : l10n.tripHandSemantics(total),
          excludeSemantics: true,
          child: GestureDetector(
            key: slotKey,
            behavior: HitTestBehavior.opaque,
            onTap: controls.returnHand,
            child: body,
          ),
        );
        return Shakeable(
          controlKey: TripControls.handKey,
          child: empty
              ? slot
              : Draggable<HandDrag>(
                  data: const HandDrag(),
                  // Drawn in the app's overlay, outside the trip's
                  // Material and its text clamp.
                  feedback: Material(
                    type: MaterialType.transparency,
                    child: MediaQuery.withClampedTextScaling(
                      maxScaleFactor: tripMaxTextScale,
                      child: TokenChip(
                        kind: TokenTint.change,
                        amountPiasters: hand.totalPiasters,
                        blocked: false,
                      ),
                    ),
                  ),
                  childWhenDragging: Opacity(opacity: 0.5, child: body),
                  child: slot,
                ),
        );
      },
    );
  }
}

class _HandBody extends StatelessWidget {
  const _HandBody({
    required this.hand,
    required this.numbers,
    required this.breakMode,
  });

  final HandView? hand;
  final NumberFormatter numbers;

  /// The drawer waits for the note to break: say so in the hand's place.
  final bool breakMode;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final hand = this.hand;
    final empty = hand == null || hand.isEmpty;
    final entries = [...?hand?.pieces.entries]
      ..sort((a, b) => b.key.compareTo(a.key));
    final pieces = [
      for (final MapEntry(key: d, value: n) in entries)
        '${numbers.piasters(d)}×${numbers.integer(n)}',
    ];
    return Container(
      constraints: const BoxConstraints(minHeight: ShapeTokens.minTouch),
      padding: const EdgeInsets.symmetric(horizontal: SpaceTokens.s),
      decoration: BoxDecoration(
        color: tokens.waraq,
        border: Border.all(color: tokens.hibr, width: ShapeTokens.borderCard),
        borderRadius: BorderRadius.circular(ShapeTokens.radiusControl),
        boxShadow: [
          BoxShadow(
            color: tokens.hibr,
            offset: hardShadowOffset(3, Directionality.of(context)),
          ),
        ],
      ),
      child: Row(
        children: [
          Text(
            l10n.tripHandLabel,
            style: TypeTokens.caption.copyWith(color: tokens.hibr, height: 1.2),
          ),
          const SizedBox(width: SpaceTokens.s),
          Expanded(
            child: Text(
              breakMode
                  ? l10n.tripBreakPick
                  : empty
                  ? l10n.tripHandEmpty
                  : pieces.join('  '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TypeTokens.caption.copyWith(
                color: tokens.hibr,
                height: 1.2,
              ),
            ),
          ),
          if (!empty)
            Text(
              numbers.piasters(hand.totalPiasters),
              style: handTotalStyle.copyWith(color: tokens.hibr, height: 1.1),
            ),
        ],
      ),
    );
  }
}

/// «رجّع»: takes back the last throw, while the engine allows it.
class UndoButton extends StatelessWidget {
  const UndoButton({super.key});

  static const buttonKey = ValueKey('trip-undo');

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final controls = TripScope.of(context).controls;
    return Shakeable(
      controlKey: TripControls.undoKey,
      child: Semantics(
        button: true,
        child: GestureDetector(
          key: buttonKey,
          behavior: HitTestBehavior.opaque,
          onTap: controls.undo,
          child: Container(
            constraints: const BoxConstraints(
              minHeight: ShapeTokens.minTouch,
              minWidth: ShapeTokens.minTouch,
            ),
            padding: const EdgeInsets.symmetric(horizontal: SpaceTokens.m),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tokens.shams,
              border: Border.all(
                color: tokens.hibr,
                width: ShapeTokens.borderCard,
              ),
              borderRadius: BorderRadius.circular(ShapeTokens.radiusControl),
            ),
            child: Text(
              AppLocalizations.of(context).tripUndo,
              style: TypeTokens.label.copyWith(color: tokens.hibr),
            ),
          ),
        ),
      ),
    );
  }
}

/// «حد معاه فكة؟»: the drawer's notes that can be broken light up, and a
/// tap on one breaks it; a second tap here cancels. At zero it fades, and a
/// tap says why.
class BreakButton extends ConsumerWidget {
  const BreakButton({super.key});

  static const buttonKey = ValueKey('trip-break');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final numbers = ref.watch(numberFormatterProvider);
    final controls = TripScope.of(context).controls;
    return TripSelector<(BreakButtonView?, bool)>(
      select: (model) =>
          (model.view?.breakButton, model.view?.breakMode ?? false),
      builder: (context, selected) {
        final (button, breakMode) = selected;
        if (button == null) return const SizedBox.shrink();
        final active = button.enabled || breakMode;
        final left = numbers.integer(button.left);
        return Shakeable(
          controlKey: TripControls.breakKey,
          child: Semantics(
            button: true,
            enabled: active,
            label: breakMode
                ? l10n.tripBreakCancel
                : l10n.tripBreakSemantics(left),
            excludeSemantics: true,
            child: GestureDetector(
              key: buttonKey,
              behavior: HitTestBehavior.opaque,
              onTap: controls.toggleBreak,
              child: Opacity(
                opacity: active ? 1 : 0.55,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      constraints: const BoxConstraints(
                        minHeight: ShapeTokens.minTouch,
                        minWidth: ShapeTokens.minTouch,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: SpaceTokens.m,
                      ),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: breakMode ? tokens.gold : tokens.shams,
                        border: Border.all(
                          color: tokens.hibr,
                          width: ShapeTokens.borderCard,
                        ),
                        borderRadius: BorderRadius.circular(
                          ShapeTokens.radiusControl,
                        ),
                      ),
                      child: Text(
                        breakMode ? l10n.tripBreakCancel : l10n.tripBreakButton,
                        maxLines: 1,
                        style: TypeTokens.label.copyWith(color: tokens.hibr),
                      ),
                    ),
                    if (!breakMode)
                      PositionedDirectional(
                        top: -SpaceTokens.s,
                        end: -SpaceTokens.s,
                        child: CountBadge(count: left),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
