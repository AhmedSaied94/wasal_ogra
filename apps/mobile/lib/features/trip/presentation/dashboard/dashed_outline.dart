// A dashed rounded outline, as CSS draws `border: 2px dashed` (`C-Trip`
// boxes 55 and 77–80): the hand slot's `sun` ring and an empty drawer cell.
import 'package:material_ui/material_ui.dart';

class DashedOutline extends CustomPainter {
  const DashedOutline({
    required this.color,
    required this.radius,
    this.width = 2,
  });

  final Color color;
  final double radius;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;
    final outline = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(width / 2),
          Radius.circular(radius - width / 2),
        ),
      );
    final dash = 3 * width;
    final gap = 2 * width;
    for (final metric in outline.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += dash + gap) {
        canvas.drawPath(metric.extractPath(d, d + dash), paint);
      }
    }
  }

  @override
  bool shouldRepaint(DashedOutline old) =>
      old.color != color || old.radius != radius || old.width != width;
}
