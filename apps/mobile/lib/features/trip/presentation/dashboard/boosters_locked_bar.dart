// The boosters' row before the tutorial is done (specs/012-m07-onboarding/
// contracts/coach.md "The locked boosters bar", `Tutorial` boxes 48–49): one
// `dashboard.raised` bar with a lock and «المساعدات بتتفتح بعد المشوار
// الخامس», which tells and does nothing.
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/components/app_icon.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

class BoostersLockedBar extends StatelessWidget {
  const BoostersLockedBar({super.key});

  static const double _icon = 16;

  @override
  Widget build(BuildContext context) {
    final text = AppLocalizations.of(context).tripBoostersLocked;
    return Semantics(
      container: true,
      label: text,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: ColorTokens.dashboardRaised,
          borderRadius: BorderRadius.all(Radius.circular(RadiusTokens.tray)),
        ),
        child: SizedBox(
          height: LayoutTokens.touchMin,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: SpaceTokens.s8,
            children: [
              const AppIcon(
                'lock',
                size: _icon,
                color: ColorTokens.dashboardMuted,
              ),
              Flexible(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TypeTokens.caption
                      .weight(600)
                      .copyWith(color: ColorTokens.dashboardMuted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
