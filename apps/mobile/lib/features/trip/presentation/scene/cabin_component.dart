// The cabin around the windows (layer 1): the wall, the window frames and
// the pillars. It never changes with the trip, so it is recorded once per
// size as a picture.
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:wassal/core/theme/tokens/shape.dart';
import 'package:wassal/features/trip/domain/scene_layout.dart';
import 'package:wassal/features/trip/presentation/scene/trip_game.dart';

class CabinComponent extends Component with HasGameReference<TripGame> {
  Picture? _picture;
  SceneLayout? _recordedFor;

  @override
  void render(Canvas canvas) {
    final layout = game.layout;
    if (layout == null) return;
    if (!identical(layout, _recordedFor)) {
      _picture?.dispose();
      _picture = _record(layout);
      _recordedFor = layout;
    }
    canvas.drawPicture(_picture!);
  }

  Picture _record(SceneLayout layout) {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    final tokens = game.tokens;
    final w = layout.width;
    final windows = layout.windows;
    final ink = Paint()
      ..color = tokens.hibr
      ..style = PaintingStyle.stroke
      ..strokeWidth = ShapeTokens.borderCard;

    // The wall under the windows.
    canvas.drawRect(
      Rect.fromLTRB(0, windows.bottom, w, layout.height),
      Paint()..color = tokens.shams,
    );
    // The sill, with a hard shadow.
    final sill = Rect.fromLTRB(0, windows.bottom, w, windows.bottom + 10);
    canvas
      ..drawRect(
        sill.shift(const Offset(0, ShapeTokens.shadowCard)),
        Paint()..color = tokens.hibr,
      )
      ..drawRect(sill, Paint()..color = tokens.tablouh)
      ..drawRect(sill, ink);

    // Pillars between three windows, and the frame.
    const pillar = 12.0;
    final frame = Paint()..color = tokens.tablouh;
    for (final x in [w / 3, w * 2 / 3]) {
      final rect = Rect.fromLTWH(x - pillar / 2, 0, pillar, windows.bottom);
      canvas
        ..drawRect(rect, frame)
        ..drawRect(rect, ink);
    }
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, windows.bottom).deflate(ShapeTokens.borderCard),
      Paint()
        ..color = tokens.tablouh
        ..style = PaintingStyle.stroke
        ..strokeWidth = ShapeTokens.borderCard * 2,
    );
    return recorder.endRecording();
  }

  @override
  void onRemove() {
    _picture?.dispose();
    super.onRemove();
  }
}
