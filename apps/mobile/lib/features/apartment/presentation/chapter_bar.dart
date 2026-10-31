// The apartment's chapter bar (specs/015-m10-apartment-story, contracts/
// apartment.md "The tab", HANDOFF `AptGoal` block 2 and `AptRooms` block 2):
// the `primary` bar both views share, opening the timeline.
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wassal/core/routing/nav_guard.dart';
import 'package:wassal/core/theme/components/app_icon.dart';
import 'package:wassal/core/theme/components/pressable.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';

class ChapterBar extends ConsumerWidget {
  const ChapterBar({
    required this.title,
    required this.trailing,
    this.trailingChild,
    this.semanticLabel,
    this.trailingIsControl = false,
    super.key,
  });

  /// «الفصل ٣ · الشبكة», or the room's own two lines.
  final Widget title;

  /// The trailing text, or [trailingChild] instead of it.
  final String trailing;
  final Widget? trailingChild;

  final String? semanticLabel;

  /// The [trailingChild] is a button of its own (`AptRoomsDone` 9): the bar
  /// then reads its label on its own node, so the child stays reachable.
  final bool trailingIsControl;

  static const double height = 56;

  /// The most of the bar a [trailingChild] takes, so the title keeps its room
  /// at 1.3x.
  static const double trailingShare = 0.4;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final radius = BorderRadius.circular(RadiusTokens.l);
    return Pressable(
      onTap: () => NavGuard.go(context, '/apartment/chapters'),
      lip: LipTokens.primaryM,
      borderRadius: radius,
      semanticLabel: trailingIsControl ? null : semanticLabel,
      child: Container(
        // 56 as drawn; a longer title at 1.3x wraps and the bar grows.
        constraints: const BoxConstraints(minHeight: height),
        padding: const EdgeInsets.symmetric(
          horizontal: SpaceTokens.s14,
          vertical: SpaceTokens.s8,
        ),
        decoration: BoxDecoration(
          color: ColorTokens.primary,
          borderRadius: radius,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) => Row(
            spacing: SpaceTokens.s10,
            children: [
              Expanded(
                child: trailingIsControl
                    ? Semantics(
                        label: semanticLabel,
                        excludeSemantics: true,
                        child: title,
                      )
                    : title,
              ),
              if (trailingChild case final child?)
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: constraints.maxWidth * trailingShare,
                  ),
                  child: child,
                )
              else
                Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: SpaceTokens.s4,
                  children: [
                    Text(
                      trailing,
                      style: TypeTokens.label.copyWith(
                        fontSize: TypeTokens.caption.fontSize,
                        fontWeight: FontWeight.w600,
                        color: ColorTokens.primarySoft,
                      ),
                    ),
                    const AppIcon(
                      'chevron_back_soft',
                      size: 16,
                      color: ColorTokens.primarySoft,
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
