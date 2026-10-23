import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/components/buttons.dart';
import 'package:wassal/features/dev/gallery/gallery_screen.dart';

/// Opens the design gallery from Home's playtest section on internal builds
/// (research R4). It pushes a plain page, so the route table is unchanged.
class GalleryEntry extends StatelessWidget {
  const GalleryEntry({super.key});

  @override
  Widget build(BuildContext context) => AppButton.secondary(
    // Developer text, as the playtest tools'.
    label: 'Design gallery',
    onTap: () => unawaited(
      Navigator.of(
        context,
        rootNavigator: true,
      ).push(MaterialPageRoute<void>(builder: (_) => const GalleryScreen())),
    ),
  );
}
