// Home's slots for later features (specs/013-m08-home-result, contracts/
// seams.md "Slots that draw something", research R10). Each is empty until
// its feature overrides it, and an empty slot takes no space.
import 'package:material_ui/material_ui.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'home_slots.g.dart';

/// M13: the gift, the tasks, the challenge and the event, at the scene
/// card's top start, [homeDailyRowHeight] high.
@Riverpod(keepAlive: true)
WidgetBuilder? homeDailyRow(Ref ref) => null;

/// The daily row's height (`C-Home` box 19: a 46 circle and its caption).
/// The barker's bubble keeps below it.
const double homeDailyRowHeight = 65;

/// M11 with B07: the morning piggy, under the savings card.
@Riverpod(keepAlive: true)
WidgetBuilder? morningPiggySlot(Ref ref) => null;

/// M10: a chapter's scene is waiting (FR-020); the savings card says so
/// instead of its bar.
@Riverpod(keepAlive: true)
bool storySceneWaiting(Ref ref) => false;
