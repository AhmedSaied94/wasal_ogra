// The change drawer (ux-spec «التابلوه» rows 2–3): eight slots in two rows,
// نص، ١، ٥، ١٠ then ٢٠، ٥٠، ١٠٠، ٢٠٠. An empty slot is dashed and faded,
// and shakes when tapped.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/theme/app_theme.dart';
import 'package:wassal/core/theme/tokens/shape.dart';
import 'package:wassal/core/theme/tokens/space.dart';
import 'package:wassal/core/theme/tokens/typography.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';
import 'package:wassal/features/trip/presentation/trip_scope.dart';
import 'package:wassal/features/trip/presentation/trip_text.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

const traySlotGap = 4.0;

class Tray extends StatelessWidget {
  const Tray({super.key});

  static Key slotKey(int denomination) => ValueKey('trip-tray-$denomination');

  @override
  Widget build(BuildContext context) {
    return TripSelector<List<TraySlotView>>(
      select: (model) => model.view?.tray ?? const [],
      equals: (a, b) =>
          a.length == b.length &&
          [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((s) => s),
      builder: (context, slots) {
        if (slots.isEmpty) return const SizedBox.shrink();
        final rows = [slots.take(4).toList(), slots.skip(4).toList()];
        return Column(
          children: [
            for (final (i, row) in rows.indexed) ...[
              if (i > 0) const SizedBox(height: traySlotGap),
              Expanded(
                child: Row(
                  children: [
                    for (final (j, slot) in row.indexed) ...[
                      if (j > 0) const SizedBox(width: traySlotGap),
                      Expanded(child: TraySlot(slot: slot)),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class TraySlot extends ConsumerWidget {
  const TraySlot({required this.slot, super.key});

  final TraySlotView slot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final numbers = ref.watch(numberFormatterProvider);
    final l10n = AppLocalizations.of(context);
    final controls = TripScope.of(context).controls;
    final d = slot.denomination;
    final empty = slot.count == 0;
    final amount = numbers.piasters(d);
    final coin = d < 500;
    final ink = empty ? tokens.waraq : tokens.hibr;
    final fill = empty
        ? Color.lerp(tokens.tablouh, tokens.waraq, 0.12)!
        : slot.breakable
        ? tokens.gold
        : tokens.waraq;
    return Shakeable(
      controlKey: TripControls.trayKey(d),
      child: Semantics(
        button: true,
        label: empty
            ? l10n.tripTrayEmptySlot(amount)
            : l10n.tripTraySlot(amount, numbers.integer(slot.count)),
        excludeSemantics: true,
        child: GestureDetector(
          key: Tray.slotKey(d),
          behavior: HitTestBehavior.opaque,
          onTap: () => controls.pick(d),
          child: CustomPaint(
            painter: empty ? _DashedBorder(color: tokens.waraq) : null,
            child: Container(
              constraints: const BoxConstraints(
                minHeight: ShapeTokens.minTouch,
                minWidth: ShapeTokens.minTouch,
              ),
              decoration: BoxDecoration(
                color: fill,
                border: empty
                    ? null
                    : Border.all(
                        color: tokens.hibr,
                        width: ShapeTokens.borderCard,
                      ),
                borderRadius: BorderRadius.circular(
                  coin ? ShapeTokens.minTouch : ShapeTokens.radiusControl / 2,
                ),
              ),
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  Text(
                    l10n.trayLabel(d, numbers),
                    maxLines: 1,
                    style: TypeTokens.title.copyWith(color: ink, height: 1.1),
                  ),
                  PositionedDirectional(
                    top: -SpaceTokens.s,
                    end: -SpaceTokens.s,
                    child: CountBadge(count: numbers.integer(slot.count)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// How many are left: a drawer slot's pieces, a booster, the breaks.
class CountBadge extends StatelessWidget {
  const CountBadge({required this.count, super.key});

  final String count;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
      padding: const EdgeInsets.symmetric(horizontal: SpaceTokens.xs),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tokens.hibr,
        borderRadius: BorderRadius.circular(ShapeTokens.radiusControl),
        border: Border.all(color: tokens.waraq, width: 1.5),
      ),
      child: Text(
        count,
        style: TypeTokens.caption.copyWith(color: tokens.waraq, height: 1.1),
      ),
    );
  }
}

/// The empty slot's dashed outline.
class _DashedBorder extends CustomPainter {
  const _DashedBorder({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final outline = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(1),
          const Radius.circular(ShapeTokens.radiusControl / 2),
        ),
      );
    for (final metric in outline.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 9) {
        canvas.drawPath(metric.extractPath(d, d + 5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) => old.color != color;
}
