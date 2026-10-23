// The dashboard (HANDOFF §4.4, `C-Trip` boxes 54–94): 258 pt, `dashboard.bg`
// with its top corners at 28, drawn over the scene's last 16 pt. Its rows
// sit at 12, 62, 112, 162 and 212: the hand and «حد معاه فكة؟», the drawer's
// two rows, the boosters, and «آخر كلام». Every control the player plays
// with outside the scene is here, in the bottom third. Text scales up to
// 1.15 (research R8).
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/trip/presentation/dashboard/boosters_row.dart';
import 'package:wassal/features/trip/presentation/dashboard/hand_slot.dart';
import 'package:wassal/features/trip/presentation/dashboard/talk_log_view.dart';
import 'package:wassal/features/trip/presentation/dashboard/tray.dart';
import 'package:wassal/features/trip/presentation/trip_text.dart';

/// A row of controls, and the gap between rows.
const dashboardRowHeight = LayoutTokens.touchMin;
const dashboardRowGap = SpaceTokens.s6;
const _padding = SpaceTokens.s12;

class TripDashboard extends StatelessWidget {
  const TripDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return TripTextScale.scope(
      context,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: ColorTokens.dashboardBg,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(RadiusTokens.sheet),
          ),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            _padding,
            _padding,
            _padding,
            MediaQuery.paddingOf(context).bottom,
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: dashboardRowHeight,
                child: Row(
                  children: [
                    Expanded(child: HandSlot()),
                    SizedBox(width: SpaceTokens.s8),
                    CallChangeButton(),
                  ],
                ),
              ),
              SizedBox(height: dashboardRowGap),
              SizedBox(
                height: 2 * dashboardRowHeight + dashboardRowGap,
                child: Tray(),
              ),
              SizedBox(height: dashboardRowGap),
              SizedBox(height: dashboardRowHeight, child: BoostersRow()),
              SizedBox(height: dashboardRowGap),
              // 36 on the board; the 10 under it leaves room for text scaled
              // up to 1.15.
              Expanded(child: LastWordsLog()),
            ],
          ),
        ),
      ),
    );
  }
}
