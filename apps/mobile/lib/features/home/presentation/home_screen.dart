// الموقف (specs/013-m08-home-result, contracts/home.md, research R12,
// HANDOFF `C-Home`, `HomeStates`): one column in the artboard's order, the
// scene card the only flexible block. Below its minimum the column
// scrolls above the bottom bar. Empty slots take no space.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/routing/new_dot_providers.dart';
import 'package:wassal/core/routing/routes.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/home/application/home_model.dart';
import 'package:wassal/features/home/application/home_slots.dart';
import 'package:wassal/features/home/domain/savings_target.dart';
import 'package:wassal/features/home/home_status_area.dart';
import 'package:wassal/features/home/presentation/debug_sheet.dart';
import 'package:wassal/features/home/presentation/home_header.dart';
import 'package:wassal/features/home/presentation/line_card.dart';
import 'package:wassal/features/home/presentation/savings_card.dart';
import 'package:wassal/features/home/presentation/start_button.dart';
import 'package:wassal/features/home/presentation/street_scene.dart';

/// `C-Home`'s rhythm: the column's gap and its bottom padding.
const double homeGap = SpaceTokens.s10;

/// The scene card's least height: the vehicle's 150 and the road.
const double homeSceneMin = 180;

/// The morning piggy's height (`C-Home` block 6), held for M11's slot.
const double homePiggyHeight = 52;

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  static const sceneKey = Key('HomeScreen.scene');
  static const scrollKey = Key('HomeScreen.scroll');

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // The apartment tab's dot while the target is affordable (FR-009).
    // Opening the tab clears it (M03).
    ref.listenManual(homeModelProvider.select((m) => m.apartmentDot), (_, dot) {
      if (!dot) return;
      // Providers can't change while widgets build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(newDotProvider(Section.apartment).notifier).show();
        }
      });
    }, fireImmediately: true);
  }

  @override
  Widget build(BuildContext context) {
    final model = ref.watch(homeModelProvider);
    final top = MediaQuery.paddingOf(context).top;
    return ColoredBox(
      color: ColorTokens.ground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              LayoutTokens.gutter,
              top,
              LayoutTokens.gutter,
              0,
            ),
            child: HomeHeader(model: model),
          ),
          // M06's banner or maintenance card sits under the header, as
          // `HomeStates` draws it, and the scene card gives up its height.
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: HomeStatusArea(child: _Body(model: model)),
            ),
          ),
        ],
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.model});

  final HomeModel model;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final piggy = ref.watch(morningPiggySlotProvider);
    final savings = model.savings;
    final line = model.line;
    final fixed = <(double, Widget)>[
      if (line != null) (HomeLineCard.height, HomeLineCard(figures: line)),
      (LayoutTokens.ctaH, HomeStartButton(model: model)),
      if (savings is! NoTarget)
        (
          HomeSavingsCard.height,
          HomeSavingsCard(
            target: savings,
            sceneWaiting: model.storySceneWaiting,
          ),
        ),
      if (piggy != null) (homePiggyHeight, Builder(builder: piggy)),
    ];
    return LayoutBuilder(
      builder: (context, box) {
        final taken =
            homeGap * (fixed.length + 2) +
            fixed.fold(0.0, (sum, block) => sum + block.$1);
        final scene = (box.maxHeight - taken).clamp(
          homeSceneMin,
          double.infinity,
        );
        return SingleChildScrollView(
          key: HomeScreen.scrollKey,
          padding: const EdgeInsets.fromLTRB(
            LayoutTokens.gutter,
            homeGap,
            LayoutTokens.gutter,
            homeGap,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: homeGap,
            children: [
              _SceneCard(model: model, height: scene),
              for (final (height, block) in fixed)
                // As drawn; a card grows with large text, and the column
                // scrolls.
                ConstrainedBox(
                  constraints: BoxConstraints(minHeight: height),
                  child: block,
                ),
            ],
          ),
        );
      },
    );
  }
}

/// The street in its card, with the daily row (M13's slot) at its top
/// start and the testers' button at its top end.
class _SceneCard extends ConsumerWidget {
  const _SceneCard({required this.model, required this.height});

  final HomeModel model;
  final double height;

  static const double _inset = SpaceTokens.s10;

  /// The barker's bubble under the daily row (`C-Home` boxes 17, 19).
  static const double _belowDaily = SpaceTokens.s6;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final daily = ref.watch(homeDailyRowProvider);
    final radius = BorderRadius.circular(RadiusTokens.scene);
    final card = DecoratedBox(
      decoration: BoxDecoration(
        color: ColorTokens.sceneSky,
        borderRadius: radius,
        boxShadow: const [LipTokens.cardBig],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            StreetScene(
              vehicle: model.vehicle,
              sign: model.signStation,
              station: model.lastStation,
              clearTop: daily == null
                  ? 0
                  : _inset + homeDailyRowHeight + _belowDaily,
            ),
            if (model.showDebug)
              const PositionedDirectional(
                top: _inset,
                end: _inset,
                child: HomeDebugButton(),
              ),
            if (daily != null)
              PositionedDirectional(
                top: _inset,
                start: _inset,
                child: Builder(builder: daily),
              ),
          ],
        ),
      ),
    );
    return TweenAnimationBuilder<double>(
      tween: Tween(end: height),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : DesignExtras.homeSceneResize,
      curve: DesignExtras.homeSceneResizeCurve,
      builder: (context, h, child) =>
          SizedBox(key: HomeScreen.sceneKey, height: h, child: child),
      child: card,
    );
  }
}
