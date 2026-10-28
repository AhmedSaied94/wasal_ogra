// The result's slots for later features (specs/013-m08-home-result,
// contracts/seams.md "Slots that draw something"). Each is empty until its
// feature overrides it, and an empty slot takes no space.
import 'package:material_ui/material_ui.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wassal/features/result/domain/result_args.dart';

part 'result_slots.g.dart';

/// M13: the daily task this trip finished: its banner, and the BONAT the
/// pay's chip shows.
typedef ResultTask = ({WidgetBuilder banner, int bonat});

/// M11: the ×2 offer and its decline link, under the pay.
typedef ResultDoubleBuilder = Widget Function(
  BuildContext context,
  ResultArgs args,
);

@Riverpod(keepAlive: true)
ResultTask? resultTaskSlot(Ref ref) => null;

@Riverpod(keepAlive: true)
ResultDoubleBuilder? resultDoubleSlot(Ref ref) => null;

/// M10: a story trip's chapter scene, before «مشوار تاني» goes on.
abstract interface class StoryAfterResult {
  Future<void> after(String tripId);
}

/// The default: nothing after a story trip.
final class NoStoryAfterResult implements StoryAfterResult {
  const NoStoryAfterResult();

  @override
  Future<void> after(String tripId) async {}
}

@Riverpod(keepAlive: true)
StoryAfterResult storyAfterResult(Ref ref) => const NoStoryAfterResult();
