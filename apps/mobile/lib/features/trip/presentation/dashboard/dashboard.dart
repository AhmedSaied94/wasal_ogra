// The dashboard (HANDOFF §4.4, `C-Trip` boxes 54–94): 258 pt, `dashboard.bg`
// with its top corners at 28, drawn over the scene's last 16 pt. Its rows
// sit at 12, 62, 112, 162 and 212: the hand and «حد معاه فكة؟», the drawer's
// two rows, the boosters, and «آخر كلام». Every control the player plays
// with outside the scene is here, in the bottom third. Text scales up to
// 1.15 (research R8). On short screens it is 226 pt, «آخر كلام» on one line
// at the top and the four rows under it (M07 contracts/compact-trip-
// layout.md "Dashboard, compact").
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/trip/presentation/dashboard/boosters_locked_bar.dart';
import 'package:wassal/features/trip/presentation/dashboard/boosters_row.dart';
import 'package:wassal/features/trip/presentation/dashboard/hand_slot.dart';
import 'package:wassal/features/trip/presentation/dashboard/talk_log_view.dart';
import 'package:wassal/features/trip/presentation/dashboard/tray.dart';
import 'package:wassal/features/trip/presentation/trip_scope.dart';
import 'package:wassal/features/trip/presentation/trip_text.dart';

/// A row of controls, and the gap between rows.
const dashboardRowHeight = LayoutTokens.touchMin;
const dashboardRowGap = SpaceTokens.s6;
const _padding = SpaceTokens.s12;

/// The compact rows: the log's line at 8, 20 high, then rows 4 apart, with
/// 6 under the last.
const compactLogTop = SpaceTokens.s8;
const compactLogHeight = 20.0;
const compactRowGap = SpaceTokens.s4;
const _compactBottom = SpaceTokens.s6;

class TripDashboard extends StatelessWidget {
  const TripDashboard({this.compact = false, super.key});

  /// The short screens' dashboard.
  final bool compact;

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
        child: compact ? _compact(context) : _regular(context),
      ),
    );
  }

  Widget _compact(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      _padding,
      compactLogTop,
      _padding,
      _compactBottom + MediaQuery.paddingOf(context).bottom,
    ),
    child: const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: compactLogHeight, child: LastWordsLog(oneLine: true)),
        SizedBox(height: compactRowGap),
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
        SizedBox(height: compactRowGap),
        SizedBox(
          height: 2 * dashboardRowHeight + compactRowGap,
          child: Tray(rowGap: compactRowGap),
        ),
        SizedBox(height: compactRowGap),
        SizedBox(height: dashboardRowHeight, child: _Boosters()),
      ],
    ),
  );

  Widget _regular(BuildContext context) => Padding(
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
        SizedBox(height: dashboardRowHeight, child: _Boosters()),
        SizedBox(height: dashboardRowGap),
        // 36 on the board; the 10 under it leaves room for text scaled
        // up to 1.15.
        Expanded(child: LastWordsLog()),
      ],
    ),
  );
}

/// Until the tutorial is done the boosters are a locked bar (FR-038).
class _Boosters extends StatelessWidget {
  const _Boosters();

  @override
  Widget build(BuildContext context) {
    final controller = TripScope.of(context).controller;
    return TripSelector<bool>(
      // The facts come with the session, which comes with the first view.
      select: (model) =>
          model.view != null &&
          (controller.session?.facts.boostersLocked ?? false),
      builder: (context, locked) =>
          locked ? const BoostersLockedBar() : const BoostersRow(),
    );
  }
}
