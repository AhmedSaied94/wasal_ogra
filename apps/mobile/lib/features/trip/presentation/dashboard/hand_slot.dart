// «في إيدك» (HANDOFF §3.4 `HandSlot`, `C-Trip` boxes 55–63): what the player
// holds as small notes and coins with `= total`, in a `sun` dashed ring on
// `dashboard.raised`. A tap returns it all to the drawer; a drag onto a
// passenger throws it, like a tap on them. While a throw can be taken back,
// the `sun` «رجّع» pill sits inside it at its end. Beside it,
// «حد معاه فكة؟» with its breaks left.
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/l10n/number_formatter.dart';
import 'package:wassal/core/theme/components/app_icon.dart';
import 'package:wassal/core/theme/components/pressable.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';
import 'package:wassal/features/trip/presentation/dashboard/dashed_outline.dart';
import 'package:wassal/features/trip/presentation/overlays/hit_areas.dart';
import 'package:wassal/features/trip/presentation/overlays/token_layer.dart';
import 'package:wassal/features/trip/presentation/trip_colors.dart';
import 'package:wassal/features/trip/presentation/trip_scope.dart';
import 'package:wassal/features/trip/presentation/trip_text.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

class HandSlot extends ConsumerWidget {
  const HandSlot({super.key});

  static const slotKey = ValueKey('trip-hand');
  static ValueKey<String> chipKey(int denomination) =>
      ValueKey('trip-hand-$denomination');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controls = TripScope.of(context).controls;
    final numbers = ref.watch(numberFormatterProvider);
    final l10n = AppLocalizations.of(context);
    return TripSelector<(HandView?, bool, bool)>(
      select: (model) {
        final view = model.view;
        final until = view?.undoUntilMs;
        return (
          view?.hand,
          view?.breakMode ?? false,
          view != null && until != null && until > view.tMs,
        );
      },
      builder: (context, selected) {
        final (hand, breakMode, undo) = selected;
        final empty = hand == null || hand.isEmpty;
        final total = numbers.piasters(hand?.totalPiasters ?? 0);
        final body = _HandBody(
          hand: hand,
          numbers: numbers,
          breakMode: breakMode,
          showTotal: !undo,
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
        final hold = Shakeable(
          controlKey: TripControls.handKey,
          child: empty
              ? slot
              : Draggable<HandDrag>(
                  data: const HandDrag(),
                  // Drawn in the app's overlay, outside the trip's text
                  // clamp.
                  feedback: Material(
                    type: MaterialType.transparency,
                    child: MediaQuery.withClampedTextScaling(
                      maxScaleFactor: TripTextScale.max,
                      child: MoneyNote(
                        kind: MoneyNoteKind.inHand,
                        amount: total,
                      ),
                    ),
                  ),
                  childWhenDragging: Opacity(opacity: 0.5, child: body),
                  child: slot,
                ),
        );
        if (!undo) return hold;
        return Stack(
          children: [
            Positioned.fill(child: hold),
            const PositionedDirectional(
              end: 0,
              top: 0,
              bottom: 0,
              child: UndoButton(),
            ),
          ],
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
    required this.showTotal,
  });

  final HandView? hand;
  final NumberFormatter numbers;

  /// The drawer waits for the note to break: say so in the hand's place.
  final bool breakMode;

  /// «رجّع» takes the total's place while it shows.
  final bool showTotal;

  static const double _radius = RadiusTokens.m;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hand = this.hand;
    final empty = hand == null || hand.isEmpty;
    final entries = [...?hand?.pieces.entries]
      ..sort((a, b) => b.key.compareTo(a.key));
    final note = TypeTokens.label.copyWith(color: ColorTokens.dashboardText);
    return CustomPaint(
      foregroundPainter: const DashedOutline(
        color: ColorTokens.sun,
        radius: _radius,
      ),
      child: Container(
        height: LayoutTokens.touchMin,
        padding: const EdgeInsets.symmetric(horizontal: SpaceTokens.s10),
        decoration: const BoxDecoration(
          color: ColorTokens.dashboardRaised,
          borderRadius: BorderRadius.all(Radius.circular(_radius)),
        ),
        child: Row(
          spacing: SpaceTokens.s6,
          children: [
            const AppIcon('hand', size: 22, color: ColorTokens.sun),
            if (breakMode)
              Expanded(
                // Two lines on narrow phones.
                child: Text(
                  l10n.tripBreakPick,
                  maxLines: 2,
                  style: note.copyWith(color: ColorTokens.sun, height: 1.15),
                ),
              )
            else if (empty)
              Expanded(
                child: Text(l10n.tripHandEmpty, maxLines: 1, style: note),
              )
            else ...[
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) => Row(
                    spacing: _Piece.gap,
                    children: [
                      for (final MapEntry(key: d, value: n) in _Piece.fitting(
                        context,
                        entries,
                        numbers,
                        constraints.maxWidth,
                      ))
                        _Piece(
                          key: HandSlot.chipKey(d),
                          denomination: d,
                          count: n,
                          numbers: numbers,
                        ),
                    ],
                  ),
                ),
              ),
              if (showTotal)
                Text(
                  l10n.tripHandTotal(numbers.piasters(hand.totalPiasters)),
                  maxLines: 1,
                  softWrap: false,
                  style: TypeTokens.numberL.copyWith(color: ColorTokens.paper),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A coin (24 round) or a note (26×20) in the hand, in its colour.
class _Piece extends StatelessWidget {
  const _Piece({
    required this.denomination,
    required this.count,
    required this.numbers,
    super.key,
  });

  final int denomination;
  final int count;
  final NumberFormatter numbers;

  static const double gap = 3;
  static const double _coin = 24;
  static const double _noteMin = 26;
  static const double _notePadding = 4;
  static final _style = TypeTokens.label
      .weight(700)
      .copyWith(color: ColorTokens.ink, height: 1);

  /// The largest pieces that fit in [width]; the total says the rest.
  static List<MapEntry<int, int>> fitting(
    BuildContext context,
    List<MapEntry<int, int>> entries,
    NumberFormatter numbers,
    double width,
  ) {
    final l10n = AppLocalizations.of(context);
    // As a Text there would lay it out: the inherited style, scale and
    // locale.
    final style = DefaultTextStyle.of(context).style.merge(_style);
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final locale = Localizations.maybeLocaleOf(context);
    double measure(String text) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: direction,
        textScaler: scaler,
        locale: locale,
        maxLines: 1,
      )..layout();
      // A paragraph lays out at its width rounded up.
      final width = painter.width.ceilToDouble();
      painter.dispose();
      return width;
    }

    final shown = <MapEntry<int, int>>[];
    var used = 0.0;
    for (final entry in entries) {
      final d = entry.key;
      var piece = TripColors.isCoin(d)
          ? _coin
          : max(
              _noteMin,
              measure(l10n.trayLabel(d, numbers)) + 2 * _notePadding,
            );
      if (entry.value > 1) {
        piece +=
            SpaceTokens.s2 +
            measure(l10n.tripTimes(numbers.integer(entry.value)));
      }
      final next = used + (shown.isEmpty ? 0 : gap) + piece;
      if (next > width) break;
      used = next;
      shown.add(entry);
    }
    return shown;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final coin = TripColors.isCoin(denomination);
    final style = _style;
    final piece = Container(
      width: coin ? _coin : null,
      height: coin ? _coin : 20,
      constraints: coin ? null : const BoxConstraints(minWidth: _noteMin),
      padding: coin
          ? null
          : const EdgeInsets.symmetric(horizontal: _notePadding),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: TripColors.denomination(denomination),
        shape: coin ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: coin
            ? null
            : const BorderRadius.all(
                Radius.circular(DesignExtras.miniNoteRadius),
              ),
      ),
      child: Text(
        l10n.trayLabel(denomination, numbers),
        maxLines: 1,
        softWrap: false,
        style: style,
      ),
    );
    if (count == 1) return piece;
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: SpaceTokens.s2,
      children: [
        piece,
        Text(
          l10n.tripTimes(numbers.integer(count)),
          style: style.copyWith(color: ColorTokens.paper),
        ),
      ],
    );
  }
}

/// «رجّع»: takes back the last throw, while the engine allows it.
class UndoButton extends StatelessWidget {
  const UndoButton({super.key});

  static const buttonKey = ValueKey('trip-undo');

  @override
  Widget build(BuildContext context) {
    final controls = TripScope.of(context).controls;
    return Shakeable(
      controlKey: TripControls.undoKey,
      child: Semantics(
        button: true,
        child: GestureDetector(
          key: buttonKey,
          behavior: HitTestBehavior.opaque,
          onTap: controls.undo,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: LayoutTokens.touchMin,
              minWidth: LayoutTokens.touchMin,
            ),
            child: Center(
              widthFactor: 1,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: SpaceTokens.s6),
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    color: ColorTokens.sun,
                    borderRadius: BorderRadius.all(
                      Radius.circular(RadiusTokens.pill),
                    ),
                    boxShadow: [LipTokens.sunS],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: SpaceTokens.s12,
                      vertical: SpaceTokens.s4,
                    ),
                    child: Text(
                      AppLocalizations.of(context).tripUndo,
                      style: DesignExtras.compactLabel.copyWith(
                        color: ColorTokens.ink,
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

/// «حد معاه فكة؟» (`C-Trip` box 61): the drawer's notes that can be broken
/// light up, and a tap on one breaks it; a second tap here cancels. At zero
/// it fades to 45%, and a tap says why.
class CallChangeButton extends ConsumerWidget {
  const CallChangeButton({super.key});

  static const buttonKey = ValueKey('trip-break');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
        final label = DesignExtras.compactLabel.copyWith(
          color: ColorTokens.ink,
        );
        final face = SizedBox(
          width: DesignExtras.callChangeWidth,
          height: LayoutTokens.touchMin,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: breakMode ? ColorTokens.sunSoft : ColorTokens.sun,
              borderRadius: const BorderRadius.all(
                Radius.circular(RadiusTokens.m),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: SpaceTokens.s12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                spacing: SpaceTokens.s4 + 1,
                children: [
                  const AppIcon(
                    'call_change',
                    size: 17,
                    color: ColorTokens.ink,
                  ),
                  Flexible(
                    child: Text(
                      breakMode ? l10n.tripBreakCancel : l10n.tripBreakButton,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.fade,
                      style: label,
                    ),
                  ),
                  if (!breakMode)
                    Text(
                      l10n.tripTimes(left),
                      style: TypeTokens.label
                          .weight(700)
                          .copyWith(color: ColorTokens.ink),
                    ),
                ],
              ),
            ),
          ),
        );
        return Shakeable(
          controlKey: TripControls.breakKey,
          child: Semantics(
            button: true,
            enabled: active,
            label: breakMode
                ? l10n.tripBreakCancel
                : l10n.tripBreakSemantics(left),
            onTap: controls.toggleBreak,
            excludeSemantics: true,
            // Still takes the tap at zero: the drawer shakes and says why.
            child: Opacity(
              opacity: active ? 1 : Pressable.disabledOpacity,
              child: Pressable(
                key: buttonKey,
                onTap: controls.toggleBreak,
                haptic: false,
                lip: LipTokens.sun,
                borderRadius: const BorderRadius.all(
                  Radius.circular(RadiusTokens.m),
                ),
                child: face,
              ),
            ),
          ),
        );
      },
    );
  }
}
