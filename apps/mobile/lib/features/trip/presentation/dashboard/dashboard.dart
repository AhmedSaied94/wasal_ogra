// The dashboard (ux-spec «التابلوه», FR-018): 230 pt at the bottom, drawn
// over the scene's last 16 pt. Every control the player plays with outside
// the scene is here, in the bottom third. The drawer and the boosters share
// a row, so every control keeps 44 pt and the text its size at 1.3× scale.
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/app_theme.dart';
import 'package:wassal/core/theme/tokens/shape.dart';
import 'package:wassal/core/theme/tokens/space.dart';
import 'package:wassal/features/trip/domain/scene_layout.dart';
import 'package:wassal/features/trip/presentation/dashboard/boosters_row.dart';
import 'package:wassal/features/trip/presentation/dashboard/hand_slot.dart';
import 'package:wassal/features/trip/presentation/dashboard/talk_log_view.dart';
import 'package:wassal/features/trip/presentation/dashboard/tray.dart';
import 'package:wassal/features/trip/presentation/trip_scope.dart';

/// The controls start below the part drawn over the scene, so all of them
/// sit under the scene's edge, in the bottom third from a 636 pt screen up.
const dashboardControlsTop = dashboardOverlap + 2;
const handRowHeight = ShapeTokens.minTouch;
const trayHeight = 2 * ShapeTokens.minTouch + traySlotGap;
const _rowGap = 4.0;

class TripDashboard extends StatelessWidget {
  const TripDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.tablouh,
        border: Border(
          top: BorderSide(color: tokens.hibr, width: ShapeTokens.borderCard),
        ),
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(ShapeTokens.radiusCard),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          SpaceTokens.m,
          dashboardControlsTop,
          SpaceTokens.m,
          SpaceTokens.s + MediaQuery.paddingOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: handRowHeight,
              child: Row(
                children: [
                  const Expanded(child: HandSlot()),
                  TripSelector<bool>(
                    select: (model) {
                      final view = model.view;
                      final until = view?.undoUntilMs;
                      return view != null && until != null && until > view.tMs;
                    },
                    builder: (context, undo) => undo
                        ? const Padding(
                            padding: EdgeInsetsDirectional.only(
                              start: SpaceTokens.s,
                            ),
                            child: UndoButton(),
                          )
                        : const SizedBox.shrink(),
                  ),
                  const SizedBox(width: SpaceTokens.s),
                  const BreakButton(),
                ],
              ),
            ),
            const SizedBox(height: _rowGap),
            const SizedBox(
              height: trayHeight,
              child: Row(
                children: [
                  Expanded(flex: 5, child: Tray()),
                  SizedBox(width: SpaceTokens.s),
                  Expanded(flex: 3, child: BoostersRow()),
                ],
              ),
            ),
            const SizedBox(height: _rowGap),
            const Expanded(child: TalkLogView()),
          ],
        ),
      ),
    );
  }
}
