// The next station's name on its sign in the window (`C-Trip` «الكوبري»,
// HANDOFF §11 "Next-station sign"). The windows draw the board in Flame,
// which draws no text; this writes the name over it in the station's letter
// colour, sliding and growing with it (`stationSign`). The strip says the
// same to a screen reader.
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/features/trip/domain/scene_layout.dart';
import 'package:wassal/features/trip/presentation/scene/windows_component.dart';
import 'package:wassal/features/trip/presentation/trip_colors.dart';
import 'package:wassal/features/trip/presentation/trip_scope.dart';

/// No text under 12 pt (constitution XI), also when a short screen scales
/// the scene down.
const _minSize = 12.0;

typedef _Next = ({String? name, int slot, int? countdownMs});

class StationSignName extends StatelessWidget {
  const StationSignName({required this.layout, super.key});

  final SceneLayout layout;

  static const nameKey = ValueKey('trip-station-sign-name');

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    return TripSelector<_Next?>(
      select: (model) {
        final strip = model.view?.strip;
        final next = strip?.chips.where((c) => c.next).firstOrNull;
        if (strip == null || next == null) return null;
        return (
          name: next.name,
          slot: next.slot,
          countdownMs: strip.countdownMs,
        );
      },
      builder: (context, next) {
        final name = next?.name;
        final sign = stationSign(
          layout,
          next?.countdownMs,
          reduceMotion: reduced,
        );
        if (next == null || name == null || sign == null) {
          return const SizedBox.shrink();
        }
        const style = DesignExtras.stationSignName;
        return Stack(
          children: [
            Positioned.fromRect(
              rect: sign.board.outerRect,
              child: Center(
                child: Text(
                  name,
                  key: nameKey,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.visible,
                  // A fixed cell, like the bubbles (research R8).
                  textScaler: TextScaler.noScaling,
                  style: style.copyWith(
                    color: TripColors.station(next.slot).letter,
                    fontSize: math.max(_minSize, style.fontSize! * sign.scale),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
