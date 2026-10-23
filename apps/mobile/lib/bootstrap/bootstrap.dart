import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/bootstrap/app.dart';

/// App entry: portrait only (FR-004), edge to edge (each screen colours the
/// system bars with `SystemBars`), one provider scope, no automatic retry so
/// a startup failure surfaces on the boot screen instead of looping.
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(ProviderScope(retry: (_, _) => null, child: const WassalApp()));
}
