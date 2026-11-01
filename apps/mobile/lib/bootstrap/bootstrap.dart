import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/bootstrap/app.dart';
import 'package:wassal/features/story/story_overrides.dart';

/// App entry: portrait only (FR-004), edge to edge (each screen colours the
/// system bars with `SystemBars`), one provider scope, no automatic retry so
/// a startup failure surfaces on the boot screen instead of looping.
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(
    ProviderScope(
      retry: (_, _) => null,
      // M10's slots (specs/015-m10-apartment-story, contracts/story-flow.md).
      overrides: storyOverrides(),
      child: const WassalApp(),
    ),
  );
}
